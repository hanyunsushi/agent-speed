using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace AgentSpeed.Core.Subscriptions;

public sealed record SubscriptionBalanceStatus(string Provider, string Name, bool Enabled, bool Configured, string Currency,
    string SiteUrl, double? Remaining, double Used, string? ErrorMessage, DateTimeOffset? RefreshedAt);
public sealed record SubscriptionTokenPair(string AccessToken, string RefreshToken);
public enum SubscriptionBalanceMode { Selected, Total, Rotation }

public static class SubscriptionBalances
{
    public static string Title(IReadOnlyList<SubscriptionBalanceStatus> statuses, IReadOnlySet<string> selected,
        SubscriptionBalanceMode mode, int rotation)
    {
        var visible = statuses.Where(s => selected.Contains(s.Provider) && s.Remaining is not null).ToArray();
        if (visible.Length == 0) return "Sub 4 Tokens";
        if (mode == SubscriptionBalanceMode.Total)
            return string.Join(" · ", visible.GroupBy(s => s.Currency.Trim().ToUpperInvariant()).OrderBy(g => g.Key, StringComparer.Ordinal)
                .Select(g => Money(g.Sum(s => s.Remaining!.Value), g.Key)));
        var status = visible[Math.Clamp(rotation, 0, visible.Length - 1)];
        return $"{status.Name} {Money(status.Remaining!.Value, status.Currency)}";
    }
    public static string Money(double amount, string currency)
    {
        var symbol = currency.Trim().ToUpperInvariant() switch { "USD" => "$", "CNY" or "RMB" => "¥", "EUR" => "€", "GBP" => "£", var other => other + " " };
        return symbol + amount.ToString("#,0.##", CultureInfo.CurrentCulture);
    }
}

public sealed class SubscriptionApiClient(HttpClient client)
{
    public static Uri? Endpoint(string baseUrl, bool refresh = false, bool forceRefresh = false)
    {
        if (!Uri.TryCreate(baseUrl.Trim(), UriKind.Absolute, out var url) || url.Scheme is not ("http" or "https")
            || string.IsNullOrEmpty(url.Host) || !string.IsNullOrEmpty(url.UserInfo)) return null;
        var path = url.AbsolutePath.Trim('/');
        if (!path.EndsWith("api/v1", StringComparison.Ordinal)) path = path.Length == 0 ? "api/v1" : path + "/api/v1";
        return new UriBuilder(url) { Path = "/" + path + (refresh ? "/auth/refresh" : "/admin/external-subscriptions/statuses"),
            Query = forceRefresh && !refresh ? "refresh=1" : "", Fragment = "" }.Uri;
    }
    public async Task<IReadOnlyList<SubscriptionBalanceStatus>> Fetch(string baseUrl, string? apiKey, string? accessToken, CancellationToken cancel = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint(baseUrl, forceRefresh: string.IsNullOrWhiteSpace(apiKey))
            ?? throw new InvalidOperationException("Sub2API URL is invalid"));
        request.Headers.Accept.Add(new("application/json"));
        if (!string.IsNullOrWhiteSpace(apiKey)) request.Headers.Add("x-api-key", apiKey.Trim());
        else if (!string.IsNullOrWhiteSpace(accessToken)) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken.Trim());
        using var response = await client.SendAsync(request, cancel).ConfigureAwait(false);
        Check(response);
        return Decode(await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false));
    }
    public async Task<SubscriptionTokenPair> Refresh(string baseUrl, string refreshToken, CancellationToken cancel = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(baseUrl, refresh: true) ?? throw new InvalidOperationException("Sub2API URL is invalid"));
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer)) { writer.WriteStartObject(); writer.WriteString("refresh_token", refreshToken.Trim()); writer.WriteEndObject(); }
        request.Content = new StringContent(Encoding.UTF8.GetString(buffer.ToArray()), Encoding.UTF8, "application/json");
        using var response = await client.SendAsync(request, cancel).ConfigureAwait(false); Check(response);
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false));
        var root = Unwrap(doc.RootElement);
        return new(root.GetProperty("access_token").GetString() ?? "", root.GetProperty("refresh_token").GetString() ?? "");
    }
    private static void Check(HttpResponseMessage response)
    {
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            throw new HttpRequestException("Sub2API credential is invalid or expired", null, response.StatusCode);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException($"Sub2API returned HTTP {(int)response.StatusCode}", null, response.StatusCode);
    }
    private static JsonElement Unwrap(JsonElement root) => root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data) ? data : root;
    public static IReadOnlyList<SubscriptionBalanceStatus> Decode(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return Unwrap(doc.RootElement).EnumerateArray().Select(r => new SubscriptionBalanceStatus(
            Text(r, "provider") ?? "", Text(r, "name") ?? "", r.GetProperty("enabled").GetBoolean(), r.GetProperty("configured").GetBoolean(),
            Text(r, "currency") ?? "", Text(r, "site_url") ?? "", Number(r, "remaining_usd"), Number(r, "used_usd") ?? 0,
            Text(r, "error_message"), DateTimeOffset.TryParse(Text(r, "refreshed_at"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) ? date : null)).ToArray();
    }
    private static string? Text(JsonElement r, string key) => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static double? Number(JsonElement r, string key) => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var n) && double.IsFinite(n) ? n : null;
}
