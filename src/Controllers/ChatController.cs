using Microsoft.AspNetCore.Mvc;
using ZavaStorefront.Services;

namespace ZavaStorefront.Controllers;

public class ChatController : Controller
{
    private readonly ChatService _chatService;
    private readonly ILogger<ChatController> _logger;

    public ChatController(ChatService chatService, ILogger<ChatController> logger)
    {
        _chatService = chatService;
        _logger = logger;
    }

    public IActionResult Index()
    {
        return View();
    }

    [HttpPost]
    public async Task<IActionResult> Send([FromBody] ChatRequest request)
    {
        if (string.IsNullOrWhiteSpace(request?.Message))
        {
            return BadRequest(new { error = "Message cannot be empty." });
        }

        _logger.LogInformation("Chat message received: {MessageLength} chars", request.Message.Length);

        var response = await _chatService.SendMessageAsync(request.Message);
        return Json(new { response });
    }
}

public class ChatRequest
{
    public string Message { get; set; } = string.Empty;
}
