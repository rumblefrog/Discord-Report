#pragma semicolon 1

#define PLUGIN_AUTHOR "Fishy"
#define PLUGIN_VERSION "1.1.0"

#include <sourcemod>
#include <smjansson>
#include <SteamWorks>
#include <morecolors>

#pragma newdecls required

ConVar cHook;

float fReportNextUse[MAXPLAYERS + 1];

int iCache[MAXPLAYERS + 1];

bool bInReason[MAXPLAYERS + 1];

char sHook[512], sHostname[64], sHost[64];

public Plugin myinfo = 
{
	name = "Discord Report",
	author = PLUGIN_AUTHOR,
	description = "Source Report => Discord",
	version = PLUGIN_VERSION,
	url = "https://keybase.io/rumblefrog"
};

public void OnPluginStart()
{
	CreateConVar("sm_discord_report_version", PLUGIN_VERSION, "Discord Report Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	cHook = CreateConVar("sm_discord_report_hook", "", "Discord Hook URL", FCVAR_PROTECTED);
	
	FindConVar("hostname").GetString(sHostname, sizeof sHostname);
	
	int iIPB = FindConVar("hostip").IntValue;
	Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", iIPB >> 24 & 0x000000FF, iIPB >> 16 & 0x000000FF, iIPB >> 8 & 0x000000FF, iIPB & 0x000000FF, FindConVar("hostport").IntValue);
	
	RegConsoleCmd("sm_report", CmdReport, "Report to admin");
	
	AutoExecConfig(true, "discord_report");
}

public void OnConfigsExecuted()
{
	cHook.GetString(sHook, sizeof sHook);
	cHook.AddChangeHook(OnConVarChanged);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == cHook)
		cHook.GetString(sHook, sizeof sHook);
}

public Action CmdReport(int iClient, int iArgs)
{
	if (StrEqual(sHook, "", false))
	{
		CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Please contact server staff to setup this plugin");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(iClient))
		return Plugin_Handled;
		
	if (OnCoolDown(iClient))
	{
		CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Please wait %.0f seconds before sending another", GetRemaining(iClient));
		return Plugin_Handled;
	}
		
	Menu mReport = new Menu(Report_Handler);
	mReport.SetTitle("Report Player");
	
	char sBuffer[MAX_NAME_LENGTH + 8], sIndex[8];
	
	for (int i = 0; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;
			
		Format(sBuffer, sizeof sBuffer, "%N", i);
		IntToString(i, sIndex, sizeof sIndex);
			
		mReport.AddItem(sIndex, sBuffer);
	}
	
	mReport.Display(iClient, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Report_Handler(Menu menu, MenuAction action, int iClient, int iItem)
{
	if (action == MenuAction_Cancel)
		delete menu;
	else if (action == MenuAction_Select)
	{
		char sIndex[8];
		
		menu.GetItem(iItem, sIndex, sizeof sIndex);
		int iTarget = StringToInt(sIndex);
		
		bInReason[iClient] = true;
		iCache[iClient] = iTarget;
		
		CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Please type a reason or \"cancel\" to cancel");
	}
}

public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
	if (bInReason[iClient])
	{	
		if (!IsValidClient(iClient) || !IsValidClient(iCache[iClient]))
		{
			ResetInReason(iClient);
			return Plugin_Continue;
		}
		
		if (!StrEqual(sArgs, "cancel", false))
			SendReport(iClient, iCache[iClient], sArgs);
		else
			CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Report cancelled");
			
		ResetInReason(iClient);
			
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void SendReport(int iClient, int iTarget, const char[] sReason)
{
	if (!IsValidClient(iClient) || !IsValidClient(iTarget))
		return;
		
	char sAuthor[MAX_NAME_LENGTH], sTarget[MAX_NAME_LENGTH], sAuthorID[32], sTargetID[32], sTargetID64[32], sJson[2048], sBuffer[256];
	
	GetClientName(iClient, sAuthor, sizeof sAuthor);
	GetClientName(iTarget, sTarget, sizeof sTarget);
	GetClientAuthId(iClient, AuthId_Steam2, sAuthorID, sizeof sAuthorID);
	GetClientAuthId(iTarget, AuthId_Steam2, sTargetID, sizeof sTargetID);
	GetClientAuthId(iTarget, AuthId_SteamID64, sTargetID64, sizeof sTargetID64);
		
	AddCoolDown(iClient);
	
	Handle jRequest = json_object();
	
	Handle jEmbeds = json_array();
	
	
	Handle jContent = json_object();
	
	json_object_set(jContent, "description", json_string("New Report"));
	json_object_set(jContent, "color", json_integer(1402304));
	
	Handle jContentAuthor = json_object();
	
	json_object_set_new(jContentAuthor, "name", json_string(sAuthor));
	Format(sBuffer, sizeof sBuffer, "https://steamcommunity.com/profiles/%s", sTargetID64);
	json_object_set_new(jContentAuthor, "url", json_string(sBuffer));
	json_object_set_new(jContent, "author", jContentAuthor);
	
	
	Handle jFields = json_array();
	
	
	Handle jFieldAuthor = json_object();
	json_object_set_new(jFieldAuthor, "name", json_string("Reporter"));
	Format(sBuffer, sizeof sBuffer, "%s (%s)", sAuthor, sAuthorID);
	json_object_set_new(jFieldAuthor, "value", json_string(sBuffer));
	json_object_set_new(jFieldAuthor, "inline", json_boolean(true));
	
	Handle jFieldTarget = json_object();
	json_object_set_new(jFieldTarget, "name", json_string("Target"));
	Format(sBuffer, sizeof sBuffer, "%s (%s)", sTarget, sTargetID);
	json_object_set_new(jFieldTarget, "value", json_string(sBuffer));
	json_object_set_new(jFieldTarget, "inline", json_boolean(true));
	
	Handle jFieldServer = json_object();
	json_object_set_new(jFieldServer, "name", json_string("Server"));
	Format(sBuffer, sizeof sBuffer, "%s (%s)", sHostname, sHost);
	json_object_set_new(jFieldServer, "value", json_string(sBuffer));
	json_object_set_new(jFieldServer, "inline", json_boolean(true));
	
	Handle jFieldReason = json_object();
	json_object_set_new(jFieldReason, "name", json_string("Reason"));
	json_object_set_new(jFieldReason, "value", json_string(sReason));
	
	json_array_append_new(jFields, jFieldAuthor);
	json_array_append_new(jFields, jFieldTarget);
	json_array_append_new(jFields, jFieldServer);
	json_array_append_new(jFields, jFieldReason);
	
	
	json_object_set_new(jContent, "fields", jFields);
	
	
	
	json_array_append_new(jEmbeds, jContent);
	json_object_set_new(jRequest, "embeds", jEmbeds);
	
	
	
	json_dump(jRequest, sJson, sizeof sJson, 0, false, false, true);
	
	#if defined DEBUG
		PrintToServer(sJson);
	#endif
	
	CloseHandle(jRequest);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sHook);
	SteamWorks_SetHTTPRequestContextValue(hRequest, iClient, iTarget);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "payload_json", sJson);
	SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPRequestComplete);
	
	if (!SteamWorks_SendHTTPRequest(hRequest))
	{
		CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Failed to send a report against %s, please try again later", sTarget);
		LogError("HTTP request failed for %s against %s", sAuthor, sTarget);
	}
}

public int OnHTTPRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int iClient, int iTarget)
{
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode204NoContent)
		CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Successfully sent a report against %N", iTarget);
	else
	{
		CPrintToChat(iClient, "{lightseagreen}[Report] {grey}Failed to send a report against %N, please try again later", iTarget);
		LogError("HTTP request failed for %N against %N", iClient, iTarget);
		
		#if defined DEBUG
			int iSize;
		
			SteamWorks_GetHTTPResponseBodySize(hRequest, iSize);
			
			char[] sBody = new char[iSize];
		
			SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, iSize);
			
			PrintToServer(sBody);
			PrintToServer("%d", eStatusCode);
		#endif
	}
	
	CloseHandle(hRequest);
}

stock bool OnCoolDown(int iClient)
{
	if (GetGameTime() < fReportNextUse[iClient])
		return true;
	return false;
}

stock void AddCoolDown(int iClient)
{
	if (OnCoolDown(iClient))
		return;
		
	fReportNextUse[iClient] = GetGameTime() + 120.0;
}

stock float GetRemaining(int iClient)
{
	if (!OnCoolDown(iClient))
		return 0.0;
		
	return fReportNextUse[iClient] - GetGameTime();
}

stock void ResetInReason(int iClient)
{
	bInReason[iClient] = false;
	iCache[iClient] = -1;
}

stock bool IsValidClient(int iClient, bool bAlive = false)
{
	if (iClient >= 1 &&
	iClient <= MaxClients &&
	IsClientConnected(iClient) &&
	IsClientInGame(iClient) &&
	!IsFakeClient(iClient) &&
	(bAlive == false || IsPlayerAlive(iClient)))
	{
		return true;
	}

	return false;
}
