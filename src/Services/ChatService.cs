using System.Text;
using System.Text.Json;

namespace ZavaStorefront.Services;

public class ChatService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ChatService> _logger;

    public ChatService(HttpClient httpClient, IConfiguration configuration, ILogger<ChatService> logger)
    {
        _httpClient = httpClient;
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<string> SendMessageAsync(string userMessage)
    {
        var endpoint = _configuration["ChatBot:Endpoint"]
            ?? throw new InvalidOperationException("ChatBot:Endpoint is not configured.");
        var apiKey = _configuration["ChatBot:ApiKey"]
            ?? throw new InvalidOperationException("ChatBot:ApiKey is not configured.");

        var requestBody = new
        {
            messages = new[]
            {
                new { role = "system", content = "You are a helpful assistant for Zava Storefront. Help customers with product inquiries and pricing questions." },
                new { role = "user", content = userMessage }
            },
            max_tokens = 800,
            temperature = 0.7
        };

        var json = JsonSerializer.Serialize(requestBody);
        var content = new StringContent(json, Encoding.UTF8, "application/json");

        _httpClient.DefaultRequestHeaders.Clear();
        _httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {apiKey}");

        var requestUri = endpoint.TrimEnd('/') + "/chat/completions";

        _logger.LogInformation("Sending chat request to Phi-4 endpoint");

        var response = await _httpClient.PostAsync(requestUri, content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Phi-4 endpoint returned {StatusCode}: {Body}", response.StatusCode, responseBody);
            return $"Error: Unable to get a response (HTTP {(int)response.StatusCode}).";
        }

        using var doc = JsonDocument.Parse(responseBody);
        var message = doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString();

        return message ?? "No response received.";
    }
}
