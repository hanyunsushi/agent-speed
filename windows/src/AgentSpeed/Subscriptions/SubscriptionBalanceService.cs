using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Windows.Threading;
using AgentSpeed.Core.Subscriptions;
using AgentSpeed.Core.Quota.Network;

namespace AgentSpeed.Subscriptions;

/// <summary>Sub4Tokens polling, rotation and credentials, owned by the Agent Speed lifecycle.</summary>
internal sealed class SubscriptionBalanceService : IDisposable
{
    private readonly DispatcherTimer _timer;
    private readonly HttpClient _http = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(20) };
    private readonly SubscriptionApiClient _client;
    private readonly string _path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AgentSpeed", "subscription-balances.json");
    private readonly CredentialManagerZcodeKeyStore _admin = new("AgentSpeed:sub2api-admin-api-key");
    private readonly CredentialManagerZcodeKeyStore _access = new("AgentSpeed:sub2api-access-token");
    private readonly CredentialManagerZcodeKeyStore _refresh = new("AgentSpeed:sub2api-refresh-token");
    private DateTimeOffset _lastAttempt = DateTimeOffset.MinValue, _lastRotation = DateTimeOffset.Now;
    private int _rotation;
    private bool _disposed;
    private readonly CancellationTokenSource _stop = new();
    public string BaseUrl { get; set; } = "https://ai.kreeper.cc";
    public HashSet<string> Selected { get; private set; } = [];
    public bool SelectionConfigured { get; set; }
    public SubscriptionBalanceMode Mode { get; set; }
    public int RefreshSeconds { get; set; } = 300;
    public int RotationSeconds { get; set; } = 10;
    public bool ShowOnTaskbar { get; set; } = true;
    public IReadOnlyList<SubscriptionBalanceStatus> Statuses { get; private set; } = [];
    public string? Error { get; private set; }
    public DateTimeOffset? LastRefresh { get; private set; }
    public bool IsRefreshing { get; private set; }
    public string Title => SubscriptionBalances.Title(Statuses, Selected, Mode, _rotation);
    public event Action? Changed;
    public string AdminKey => _admin.Read() ?? "";
    public string AccessToken => _access.Read() ?? "";
    public string RefreshToken => _refresh.Read() ?? "";
    public SubscriptionBalanceService(Dispatcher dispatcher)
    {
        _client = new(_http); Load();
        _timer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, Tick, dispatcher);
        _timer.Start(); _ = Refresh();
    }
    private void Tick(object? sender, EventArgs e)
    {
        var now = DateTimeOffset.Now;
        if ((now - _lastAttempt).TotalSeconds >= Math.Clamp(RefreshSeconds, 30, 3600)) _ = Refresh();
        if (Mode == SubscriptionBalanceMode.Rotation && (now - _lastRotation).TotalSeconds >= Math.Clamp(RotationSeconds, 3, 300))
        {
            _lastRotation = now;
            var count = Statuses.Count(s => Selected.Contains(s.Provider) && s.Remaining is not null);
            _rotation = count == 0 ? 0 : (_rotation + 1) % count; Changed?.Invoke();
        }
    }
    public bool SaveCredentials(string admin, string access, string refresh)
    {
        bool Store(CredentialManagerZcodeKeyStore store, string value)
        {
            if (string.IsNullOrWhiteSpace(value)) { store.Remove(); return true; }
            return store.Save(value.Trim());
        }
        if (!Store(_admin, admin) || !Store(_access, access) || !Store(_refresh, refresh))
        { Error = "Cannot save credentials in Windows Credential Manager"; Changed?.Invoke(); return false; }
        return true;
    }
    public async Task Refresh()
    {
        if (IsRefreshing || _disposed) return;
        IsRefreshing = true; _lastAttempt = DateTimeOffset.Now; Changed?.Invoke();
        var requestedBase = BaseUrl;
        try
        {
            var admin = AdminKey; var access = AccessToken; var refresh = RefreshToken;
            if (string.IsNullOrWhiteSpace(admin) && string.IsNullOrWhiteSpace(access) && string.IsNullOrWhiteSpace(refresh))
                throw new InvalidOperationException("Set the Sub2API URL and Admin API Key in connection settings");
            async Task Renew()
            {
                if (string.IsNullOrEmpty(refresh)) throw new InvalidOperationException("A refresh token is required");
                var pair = await _client.Refresh(requestedBase, refresh, _stop.Token);
                access = pair.AccessToken; refresh = string.IsNullOrWhiteSpace(pair.RefreshToken) ? refresh : pair.RefreshToken;
                if (!SaveCredentials("", access, refresh)) throw new InvalidOperationException("Cannot save refreshed credentials");
            }
            if (string.IsNullOrEmpty(admin) && string.IsNullOrEmpty(access)) await Renew();
            IReadOnlyList<SubscriptionBalanceStatus> next;
            try { next = await _client.Fetch(requestedBase, admin, access, _stop.Token); }
            catch (HttpRequestException e) when (string.IsNullOrEmpty(admin) && e.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            { await Renew(); next = await _client.Fetch(requestedBase, null, access, _stop.Token); }
            if (BaseUrl != requestedBase || _disposed) return;
            Statuses = next;
            if (!SelectionConfigured) { Selected = next.Where(s => s.Enabled).Select(s => s.Provider).ToHashSet(); SelectionConfigured = true; }
            Selected.IntersectWith(next.Select(s => s.Provider)); LastRefresh = DateTimeOffset.Now; Error = null;
            Save();
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
        catch (Exception e) when (e is HttpRequestException or JsonException or KeyNotFoundException or FormatException or InvalidOperationException or IOException or TaskCanceledException)
        { Error = e is JsonException or KeyNotFoundException or FormatException ? "Sub2API returned an invalid response" : e.Message; }
        finally { IsRefreshing = false; if (!_disposed) Changed?.Invoke(); }
    }
    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            using var buffer = new MemoryStream();
            using (var w = new Utf8JsonWriter(buffer))
            {
                w.WriteStartObject(); w.WriteString("baseUrl", BaseUrl); w.WriteString("mode", Mode.ToString());
                w.WriteNumber("refreshSeconds", Math.Clamp(RefreshSeconds, 30, 3600)); w.WriteNumber("rotationSeconds", Math.Clamp(RotationSeconds, 3, 300));
                w.WriteBoolean("showOnTaskbar", ShowOnTaskbar); w.WriteBoolean("selectionConfigured", SelectionConfigured); w.WriteStartArray("selected");
                foreach (var id in Selected.Order()) w.WriteStringValue(id);
                w.WriteEndArray(); w.WriteEndObject();
            }
            File.WriteAllBytes(_path + ".tmp", buffer.ToArray()); File.Move(_path + ".tmp", _path, true);
        }
        catch (IOException) { Error = "Cannot save subscription settings"; }
        _rotation = 0; Changed?.Invoke();
    }
    private void Load()
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(_path)); var r = doc.RootElement;
            BaseUrl = r.GetProperty("baseUrl").GetString() ?? BaseUrl;
            if (Enum.TryParse<SubscriptionBalanceMode>(r.GetProperty("mode").GetString(), out var mode)) Mode = mode;
            RefreshSeconds = Math.Clamp(r.GetProperty("refreshSeconds").GetInt32(), 30, 3600);
            RotationSeconds = Math.Clamp(r.GetProperty("rotationSeconds").GetInt32(), 3, 300);
            ShowOnTaskbar = r.GetProperty("showOnTaskbar").GetBoolean(); SelectionConfigured = r.GetProperty("selectionConfigured").GetBoolean();
            Selected = r.GetProperty("selected").EnumerateArray().Select(x => x.GetString()!).ToHashSet();
        }
        catch (Exception e) when (e is IOException or JsonException or KeyNotFoundException or InvalidOperationException or UnauthorizedAccessException) { }
    }
    public void Dispose() { _disposed = true; _timer.Stop(); _stop.Cancel(); _http.Dispose(); _stop.Dispose(); }
}
