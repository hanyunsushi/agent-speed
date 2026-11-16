using System.Net;
using System.Text;
using AgentSpeed.Core.Subscriptions;

namespace AgentSpeed.Core.Tests;

public sealed class SubscriptionBalanceTests
{
    [Theory]
    [InlineData("https://example.invalid", "/api/v1/admin/external-subscriptions/statuses")]
    [InlineData("https://example.invalid/api/v1/", "/api/v1/admin/external-subscriptions/statuses")]
    [InlineData("https://example.invalid/base", "/base/api/v1/admin/external-subscriptions/statuses")]
    public void EndpointPreservesApiPrefix(string value, string path)
    {
        Assert.Equal(path, SubscriptionApiClient.Endpoint(value)!.AbsolutePath);
        Assert.Empty(SubscriptionApiClient.Endpoint(value)!.Query);
        Assert.Equal("?refresh=1", SubscriptionApiClient.Endpoint(value, forceRefresh: true)!.Query);
    }
    [Fact] public void InvalidEndpointsAndCurrenciesAreNotGuessed()
    {
        Assert.Null(SubscriptionApiClient.Endpoint("file:///tmp/balance"));
        Assert.Null(SubscriptionApiClient.Endpoint("not a url"));
        var statuses = SubscriptionApiClient.Decode("""{"data":[{"provider":"a","name":"A","enabled":true,"configured":true,"currency":"EUR","site_url":"https://example.invalid","used_usd":2,"remaining_usd":8.5}]}""");
        Assert.Equal("EUR", statuses[0].Currency); Assert.Equal(8.5, statuses[0].Remaining);
        Assert.Contains("€8.5", SubscriptionBalances.Title(statuses, new HashSet<string> { "a" }, SubscriptionBalanceMode.Selected, 0));
    }
    [Fact] public void TotalsKeepCurrenciesSeparateAndRotationSkipsUnavailable()
    {
        SubscriptionBalanceStatus S(string id, string currency, double? remaining) => new(id, id, true, true, currency, "", remaining, 0, null, null);
        var statuses = new[] { S("missing", "USD", null), S("a", "USD", 10), S("b", "USD", 20), S("c", "CNY", 50) };
        var selected = statuses.Select(s => s.Provider).ToHashSet();
        Assert.Equal("¥50 · $30", SubscriptionBalances.Title(statuses, selected, SubscriptionBalanceMode.Total, 0));
        Assert.Equal("b $20", SubscriptionBalances.Title(statuses, selected, SubscriptionBalanceMode.Rotation, 1));
        Assert.Equal("Sub 4 Tokens", SubscriptionBalances.Title(statuses, new HashSet<string>(), SubscriptionBalanceMode.Total, 0));
    }
    [Fact] public async Task AdminKeyUsesCachedStatusAndLegacyUsesBearer()
    {
        using var handler = new CaptureHandler(); using var http = new HttpClient(handler); var client = new SubscriptionApiClient(http);
        await client.Fetch("https://example.invalid", "test-admin", "test-access");
        Assert.Equal("test-admin", handler.ApiKey); Assert.Null(handler.Authorization); Assert.Empty(handler.Query!);
        await client.Fetch("https://example.invalid", null, "test-access");
        Assert.Equal("Bearer test-access", handler.Authorization); Assert.Equal("?refresh=1", handler.Query);
        var pair = await client.Refresh("https://example.invalid", "test-refresh");
        Assert.Equal("new-access", pair.AccessToken); Assert.Equal("new-refresh", pair.RefreshToken);
    }
    private sealed class CaptureHandler : HttpMessageHandler
    {
        public string? ApiKey, Authorization, Query;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            ApiKey = request.Headers.TryGetValues("x-api-key", out var keys) ? keys.Single() : null;
            Authorization = request.Headers.Authorization?.ToString(); Query = request.RequestUri!.Query;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(request.Method == HttpMethod.Post
                ? """{"data":{"access_token":"new-access","refresh_token":"new-refresh"}}""" : "[]", Encoding.UTF8, "application/json") });
        }
    }
}
