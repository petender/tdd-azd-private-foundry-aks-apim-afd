using Azure.AI.Projects;
using FoundryChat.Web.Models;

namespace FoundryChat.Web.Services;

public class ChatService(AIProjectClient projectClient, string agentId)
{
    private readonly AgentsClient _agents = projectClient.GetAgentsClient();

    public async Task<(string ThreadId, string Reply)> SendMessageAsync(
        string userMessage,
        string? threadId = null)
    {
        // Resolve or create the agent. If no agentId is supplied, use the first available agent.
        var resolvedAgentId = agentId;
        if (string.IsNullOrEmpty(resolvedAgentId))
        {
            var list = _agents.GetAgentsAsync();
            await foreach (var a in list)
            {
                resolvedAgentId = a.Id;
                break;
            }
        }

        if (string.IsNullOrEmpty(resolvedAgentId))
            resolvedAgentId = await CreateDefaultAgentAsync();

        // Create a new thread or reuse an existing one.
        AgentThread thread;
        if (string.IsNullOrEmpty(threadId))
            thread = await _agents.CreateThreadAsync();
        else
            thread = await _agents.GetThreadAsync(threadId);

        await _agents.CreateMessageAsync(thread.Id, MessageRole.User, userMessage);

        var run = await _agents.CreateRunAsync(thread.Id, resolvedAgentId);

        // Poll until the run is in a terminal state.
        while (run.Status == RunStatus.Queued || run.Status == RunStatus.InProgress)
        {
            await Task.Delay(500);
            run = await _agents.GetRunAsync(thread.Id, run.Id);
        }

        // Collect the most recent assistant message.
        var messages = _agents.GetMessagesAsync(thread.Id, order: ListSortOrder.Descending);
        await foreach (var msg in messages)
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

    // Creates a minimal fallback agent when none exist in the project.
    private async Task<string> CreateDefaultAgentAsync()
    {
        var agent = await _agents.CreateAgentAsync(
            model: "gpt-4o",
            name: "FoundryChatAgent",
            instructions: "You are a helpful AI assistant. Answer concisely and clearly.");
        return agent.Value.Id;
    }
}
