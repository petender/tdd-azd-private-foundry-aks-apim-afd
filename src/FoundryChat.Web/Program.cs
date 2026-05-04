using Azure.AI.Projects;
using Azure.Identity;
using FoundryChat.Web.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();

var foundryEndpoint = builder.Configuration["FOUNDRY_PROJECT_ENDPOINT"]
    ?? builder.Configuration["FoundryProjectEndpoint"]
    ?? throw new InvalidOperationException("FOUNDRY_PROJECT_ENDPOINT is not configured.");

var agentId = builder.Configuration["FOUNDRY_AGENT_ID"]
    ?? builder.Configuration["FoundryAgentId"]
    ?? string.Empty;

builder.Services.AddSingleton(_ =>
    new AIProjectClient(new Uri(foundryEndpoint), new DefaultAzureCredential()));

builder.Services.AddScoped<ChatService>(sp =>
{
    var client = sp.GetRequiredService<AIProjectClient>();
    return new ChatService(client, agentId);
});

var app = builder.Build();

if (!app.Environment.IsDevelopment())
    app.UseExceptionHandler("/Error");

app.UseStaticFiles();
app.UseRouting();
app.MapRazorPages();

app.Run();
