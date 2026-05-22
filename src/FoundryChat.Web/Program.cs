using Azure.AI.Agents.Persistent;
using Azure.Identity;
using FoundryChat.Web.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();

var agentsEndpoint = builder.Configuration["FOUNDRY_AGENTS_ENDPOINT"]
    ?? builder.Configuration["FOUNDRY_PROJECT_ENDPOINT"]
    ?? throw new InvalidOperationException("FOUNDRY_AGENTS_ENDPOINT is not configured.");

var agentId = builder.Configuration["FOUNDRY_AGENT_ID"]
    ?? builder.Configuration["FoundryAgentId"]
    ?? string.Empty;

builder.Services.AddSingleton(_ =>
    new PersistentAgentsClient(agentsEndpoint, new DefaultAzureCredential()));

builder.Services.AddScoped<ChatService>(sp =>
{
    var client = sp.GetRequiredService<PersistentAgentsClient>();
    return new ChatService(client, agentId);
});

var app = builder.Build();

if (!app.Environment.IsDevelopment())
    app.UseExceptionHandler("/Error");

app.UseStaticFiles();
app.UseRouting();
app.MapRazorPages();

app.Run();
