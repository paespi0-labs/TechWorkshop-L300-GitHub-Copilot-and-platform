using System.Text;
using System.Text.Json;
using Azure.Identity;

namespace ZavaStorefront.Services;

public class ChatService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ChatService> _logger;
    private static readonly DefaultAzureCredential _credential = new();

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

        var tokenRequestContext = new Azure.Core.TokenRequestContext(["https://cognitiveservices.azure.com/.default"]);
        var accessToken = await _credential.GetTokenAsync(tokenRequestContext);

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

        var requestUri = endpoint.TrimEnd('/') + "/chat/completions?api-version=2024-10-21";
        var request = new HttpRequestMessage(HttpMethod.Post, requestUri);
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken.Token);
        request.Content = new StringContent(JsonSerializer.Serialize(requestBody), Encoding.UTF8, "application/json");

        _logger.LogInformation("Sending chat request using managed identity");

        var response = await _httpClient.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("AI endpoint returned {StatusCode}: {Body}", response.StatusCode, responseBody);
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
