namespace FoundryChat.Web.Models;

public class ChatSession
{
    public string? ThreadId { get; set; }
    public List<ChatMessage> Messages { get; set; } = [];
}
