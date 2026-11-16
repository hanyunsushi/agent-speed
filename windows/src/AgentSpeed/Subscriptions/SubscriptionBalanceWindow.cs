using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using AgentSpeed.Core.Subscriptions;

namespace AgentSpeed.Subscriptions;

/// <summary>Original Sub4Tokens content and controls, hosted by Agent Speed on Windows.</summary>
internal sealed class SubscriptionBalanceWindow : Window
{
    private readonly SubscriptionBalanceService _service;
    private readonly StackPanel _rows = new();
    private readonly TextBlock _updated = new(), _error = new() { Foreground = Brushes.DarkOrange, TextWrapping = TextWrapping.Wrap };
    private readonly TextBox _base = new();
    private readonly PasswordBox _admin = new(), _access = new(), _refresh = new();
    private readonly Button _refreshButton = new() { Content = "Refresh", HorizontalAlignment = HorizontalAlignment.Right };
    public SubscriptionBalanceWindow(SubscriptionBalanceService service)
    {
        _service = service;
        Title = "Sub 4 Tokens"; Width = 400; Height = 650; MinWidth = 360; MaxHeight = 850;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var panel = new StackPanel { Margin = new Thickness(16) };
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        panel.Children.Add(new TextBlock { Text = "Customize Sub 4 Tokens", FontSize = 17, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(_updated); panel.Children.Add(_refreshButton); panel.Children.Add(_error); panel.Children.Add(_rows);
        _refreshButton.Click += async (_, _) => await service.Refresh();
        panel.Children.Add(new Separator { Margin = new Thickness(0, 14, 0, 8) });
        var mode = new ComboBox { ItemsSource = new[] { "Selected balance", "Total by currency", "Rotate selected" }, SelectedIndex = (int)service.Mode };
        Row(panel, "Display", mode); mode.SelectionChanged += (_, _) => { service.Mode = (SubscriptionBalanceMode)mode.SelectedIndex; service.Save(); };
        var refreshSeconds = new TextBox { Text = service.RefreshSeconds.ToString(CultureInfo.InvariantCulture) };
        var rotationSeconds = new TextBox { Text = service.RotationSeconds.ToString(CultureInfo.InvariantCulture) };
        Row(panel, "Refresh seconds (30–3600)", refreshSeconds); Row(panel, "Rotate seconds (3–300)", rotationSeconds);
        var apply = new Button { Content = "Apply intervals", HorizontalAlignment = HorizontalAlignment.Left };
        apply.Click += (_, _) =>
        {
            if (int.TryParse(refreshSeconds.Text, out var refresh) && refresh is >= 30 and <= 3600 && int.TryParse(rotationSeconds.Text, out var rotation) && rotation is >= 3 and <= 300)
            { service.RefreshSeconds = refresh; service.RotationSeconds = rotation; service.Save(); }
            else _error.Text = "Refresh must be 30–3600 seconds; rotation must be 3–300 seconds.";
        };
        panel.Children.Add(apply);
        var shown = new CheckBox { Content = "Show balance text on taskbar", IsChecked = service.ShowOnTaskbar, Margin = new Thickness(0, 8, 0, 8) };
        shown.Checked += (_, _) => { service.ShowOnTaskbar = true; service.Save(); };
        shown.Unchecked += (_, _) => { service.ShowOnTaskbar = false; service.Save(); }; panel.Children.Add(shown);
        var connection = new StackPanel();
        _base.Text = service.BaseUrl; _admin.Password = service.AdminKey; _access.Password = service.AccessToken; _refresh.Password = service.RefreshToken;
        Row(connection, "Sub2API URL", _base); Row(connection, "Global Admin API Key", _admin);
        var legacy = new StackPanel(); Row(legacy, "Access token", _access); Row(legacy, "Refresh token", _refresh);
        connection.Children.Add(new Expander { Header = "Legacy login tokens", Content = legacy });
        var sync = new Button { Content = "Sync providers", Margin = new Thickness(0, 8, 0, 8) };
        sync.Click += async (_, _) =>
        {
            if (service.IsRefreshing) return;
            if (SubscriptionApiClient.Endpoint(_base.Text) is null) { _error.Text = "Sub2API URL is invalid"; return; }
            service.BaseUrl = _base.Text.Trim();
            if (!service.SaveCredentials(_admin.Password, _access.Password, _refresh.Password)) return;
            service.Save(); await service.Refresh();
        };
        connection.Children.Add(sync);
        panel.Children.Add(new Expander { Header = "Sub2API connection", Content = connection });
        panel.Children.Add(new TextBlock { Text = "A6API Cookie stays in Sub2API. Credentials are saved in Windows Credential Manager.",
            FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) });
        service.Changed += Update; Closed += (_, _) => service.Changed -= Update; Update();
    }
    private static void Row(Panel panel, string name, Control input)
    {
        panel.Children.Add(new TextBlock { Text = name, Margin = new Thickness(0, 8, 0, 3) });
        input.MinHeight = 26; panel.Children.Add(input);
    }
    private void Update()
    {
        _updated.Text = _service.LastRefresh is { } at ? $"Updated {at:t}" : "Waiting for first refresh";
        _error.Text = _service.Error ?? ""; _refreshButton.IsEnabled = !_service.IsRefreshing;
        _rows.Children.Clear();
        if (_service.Statuses.Count == 0) _rows.Children.Add(new TextBlock { Text = "No balances yet", Margin = new Thickness(0, 14, 0, 14) });
        foreach (var status in _service.Statuses)
        {
            var row = new Grid { Margin = new Thickness(0, 8, 0, 0) };
            row.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
            var selected = new CheckBox { Content = status.Name, IsChecked = _service.Selected.Contains(status.Provider), ToolTip = status.ErrorMessage ?? status.Currency };
            void Select(bool enabled) { if (enabled) _service.Selected.Add(status.Provider); else _service.Selected.Remove(status.Provider); _service.SelectionConfigured = true; _service.Save(); }
            selected.Checked += (_, _) => Select(true); selected.Unchecked += (_, _) => Select(false); row.Children.Add(selected);
            var amount = new TextBlock { Text = status.Remaining is { } value ? SubscriptionBalances.Money(value, status.Currency) : "—", FontFamily = new FontFamily("Consolas") };
            Grid.SetColumn(amount, 1); row.Children.Add(amount); _rows.Children.Add(row);
        }
    }
}
