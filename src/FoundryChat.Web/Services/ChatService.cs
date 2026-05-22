using Azure.AI.Agents.Persistent;
using FoundryChat.Web.Models;

namespace FoundryChat.Web.Services;

public class ChatService(PersistentAgentsClient agentsClient, string agentId)
{
    private readonly PersistentAgentsClient _agents = agentsClient;

    public async Task<(string ThreadId, string Reply)> SendMessageAsync(
        string userMessage,
        string? threadId = null)
    {
        var resolvedAgentId = agentId;
        if (string.IsNullOrEmpty(resolvedAgentId))
        {
            await foreach (var a in _agents.Administration.GetAgentsAsync())
            {
                resolvedAgentId = a.Id;
                break;
            }
        }

        if (string.IsNullOrEmpty(resolvedAgentId))
            resolvedAgentId = await CreateDefaultAgentAsync();

        PersistentAgentThread thread;
        if (string.IsNullOrEmpty(threadId))
            thread = await _agents.Threads.CreateThreadAsync();
        else
            thread = await _agents.Threads.GetThreadAsync(threadId);

        await _agents.Messages.CreateMessageAsync(thread.Id, MessageRole.User, userMessage);

        ThreadRun run = await _agents.Runs.CreateRunAsync(thread.Id, resolvedAgentId);

        while (run.Status == RunStatus.Queued || run.Status == RunStatus.InProgress)
        {
            await Task.Delay(500);
            run = await _agents.Runs.GetRunAsync(thread.Id, run.Id);
        }

        await foreach (var msg in _agents.Messages.GetMessagesAsync(thread.Id, order: ListSortOrder.Descending))
        {
            if (msg.Role == MessageRole.Agent)
            {
                var text = msg.ContentItems
                    .OfType<MessageTextContent>()
                    .FirstOrDefault()?.Text ?? string.Empty;
                return (thread.Id, text);
            }
        }

        return (thread.Id, "(no reply)");
    }

    private async Task<string> CreateDefaultAgentAsync()
    {
        PersistentAgent agent = await _agents.Administration.CreateAgentAsync(
            model: "gpt-4o",
            name: "FoundryChatAgent",
            instructions: "You are a helpful AI assistant. Answer concisely and clearly.");
        return agent.Id;
    }
}
