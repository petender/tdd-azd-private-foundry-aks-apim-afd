using FoundryChat.Web.Models;
using FoundryChat.Web.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FoundryChat.Web.Pages;

public class IndexModel(ChatService chatService) : PageModel
{
    [BindProperty]
    public string UserInput { get; set; } = string.Empty;

    [BindProperty]
    public ChatSession Session { get; set; } = new();

    public string ErrorMessage { get; set; } = string.Empty;

    public void OnGet() { }

    public async Task<IActionResult> OnPostAsync()
    {
        if (string.IsNullOrWhiteSpace(UserInput))
            return Page();

        Session.Messages.Add(new ChatMessage { Role = "user", Content = UserInput });

        try
        {
            var (threadId, reply) = await chatService.SendMessageAsync(UserInput, Session.ThreadId);
            Session.ThreadId = threadId;
            Session.Messages.Add(new ChatMessage { Role = "assistant", Content = reply });
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Error contacting AI agent: {ex.Message}";
        }

        UserInput = string.Empty;
        return Page();
    }
}
