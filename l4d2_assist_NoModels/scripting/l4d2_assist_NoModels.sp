#pragma semicolon 1
#pragma newdecls required //強制1.7以後的新語法

#include <sourcemod>
#include <multicolors>

#define PLUGIN_VERSION "1.8"
#define ZOMBIECLASS_TANK 8

#define IsSurvivor(%0) (GetClientTeam(%0) == 2)
#define IsWitch(%0) (g_bIsWitch[%0])
#define MAXENTITIES 2048

ConVar cvarEnable;
ConVar cvarTank;

bool AssistFlag;

int Damage[MAXPLAYERS+1][MAXPLAYERS+1];
static int g_iTankCvarHealth;
ConVar g_hTankHealth, g_hDifficulty, g_hGameMode;
//char Temp1[] = "|| Assist: ";
char Temp2[] = ", ";
char Temp3[] = " (";
char Temp4[] = " dmg)";
char Temp5[] = "\x05";
char Temp6[] = "\x01";
bool g_bIsWitch[MAXENTITIES];							// Membership testing for fast witch checking
int g_iWitchidHealth[MAXENTITIES]								= 1000;	// Default
int 	g_iWitchHealth;
int g_iAccumulatedWitchDamage[MAXENTITIES];							// Current witch health = witch health - accumulated
bool g_bShouldAnnounceWitchDamage[MAXENTITIES]				= false;
int	g_iOffset_Incapacitated     = 0;                // Used to check if tank is dying

public Plugin myinfo = 
{
	name = "L4D Assistance System",
	author = "[E]c & Max Chu, SilverS & ViRaGisTe & HarryPotter",
	description = "Show assists made by survivors",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=123811"
}

public void OnPluginStart()
{
	CreateConVar("sm_assist_version", PLUGIN_VERSION, "Assistance System Version", FCVAR_NOTIFY);
	cvarTank = CreateConVar("sm_assist_tank_only", "1", "Enables this will show only damage done to Tank.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvarEnable = CreateConVar("sm_assist_enable", "1", "Enables this plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookEvent("player_hurt", Event_Player_Hurt);
	HookEvent("player_death", Event_Player_Death);
	HookEvent("round_end", Event_Round_End);
	HookEvent("round_start", Event_Round_Start);
	HookEvent("witch_killed", Event_Witch_Death);
	HookEvent("player_incapacitated", Event_PlayerIncapacitated);
	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("infected_hurt", Event_InfectedHurt);
	
	g_hTankHealth		= FindConVar("z_tank_health");
	g_hDifficulty		= FindConVar("z_difficulty");
	g_hGameMode			= FindConVar("mp_gamemode");
	
	g_iTankCvarHealth = RoundFloat(g_hTankHealth.FloatValue * (IsVersusGameMode() ? 1.5 : GetCoopMultiplie()));
	g_iOffset_Incapacitated = FindSendPropInfo("Tank", "m_isIncapacitated");
	
	g_hDifficulty.AddChangeHook(OnConvarChange_TankHealth);
	g_hTankHealth.AddChangeHook(OnConvarChange_TankHealth);
	g_hGameMode.AddChangeHook(OnConvarChange_TankHealth);
	
	AutoExecConfig(true, "l4d2_assist");
}

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast) 
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (attacker == 0 ||								// Killed by world?
		!IsWitch(GetEventInt(event, "entityid")) ||		// Tracking witch damage only
		!IsClientInGame(attacker) ||
		!IsSurvivor(attacker)							// Claws
		) return;

	int damage = GetEventInt(event, "amount");
	g_iAccumulatedWitchDamage[GetEventInt(event, "entityid")] += damage;
}

public Action Event_PlayerIncapacitated(Event event, const char[] name, bool dontBroadcast) 
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int witchid = GetEventInt(event, "attackerentid");
	if (!IsWitch(witchid)||
	!g_bShouldAnnounceWitchDamage[witchid]					// Prevent double print on witch incapping 2 players (rare)
	) return Plugin_Continue;

	if(victim<1 || victim > MaxClients || !IsClientConnected(victim) || !IsClientInGame(victim)) return Plugin_Continue;
	
	int health = g_iWitchidHealth[witchid] - g_iAccumulatedWitchDamage[witchid];
	if (health < 0) health = 0;
	
	CPrintToChatAll("{default}[{olive}TS{default}]{green} Witch{default} had{green} %d{default} health remaining.", health);
	CPrintToChatAll("{green}[提示]{lightgreen} %N {default}反被 {green}Witch {olive}爆☆殺{default}.", victim);
	
	g_iAccumulatedWitchDamage[witchid] = 0;
	g_bShouldAnnounceWitchDamage[witchid] = false;
	return Plugin_Continue;
}

public Action Event_Round_Start(Event event, const char[] name, bool dontBroadcast) 
{
	g_iWitchHealth = GetConVarInt(FindConVar("z_witch_health"));
	if (GetConVarInt(cvarEnable))
	{
		for (int i = 0; i <= MAXPLAYERS; i++)
		{
			for (int a = 1; a <= MAXPLAYERS; a++)
			{
				Damage[i][a] = 0;
			}
		}
	}
	ResetWitchTracking();
}

void ResetWitchTracking()
{
	for (int i = MaxClients + 1; i < MAXENTITIES; i++) g_bIsWitch[i] = false;
}

public Action Event_Player_Hurt(Event event, const char[] name, bool dontBroadcast) 
{
	if (GetConVarInt(cvarEnable))
	{
		int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		int victim = GetClientOfUserId(GetEventInt(event, "userid"));
		if (GetConVarInt(cvarTank))
		{
			int class = GetEntProp(victim, Prop_Send, "m_zombieClass");
			if (class != ZOMBIECLASS_TANK || IsTankDying(victim))
				return Plugin_Handled;
		}
		if ((victim != 0) && (attacker != 0))
		{
			if(GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 3 )
			{
				int DamageHealth = GetEventInt(event, "dmg_health");
				//if (DamageHealth < 1024)
				//{
				if (victim != attacker && GetClientTeam(victim) != GetClientTeam(attacker))
				{
					Damage[attacker][victim] += DamageHealth;
				}
				//}
			}
		}
	}
	return Plugin_Continue;
}

public Action Event_Player_Death(Event event, const char[] name, bool dontBroadcast) 
{
	if (GetConVarInt(cvarEnable))
	{
		int victim = GetClientOfUserId(GetEventInt(event, "userid"));
		int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

		if (attacker == 0)
		{ // Check for a witch-related death (black & white survivor failing or no-incap configs e.g. 1v1)
			int witchid = GetEventInt(event, "attackerentid");
			if (!IsWitch(witchid)||
			!g_bShouldAnnounceWitchDamage[witchid]					// Prevent double print on witch incapping 2 players (rare)
			) return Plugin_Continue;
			
			if(victim<1 || victim > MaxClients || !IsClientConnected(victim) || !IsClientInGame(victim)) return Plugin_Continue;
			
			int health = g_iWitchidHealth[witchid] - g_iAccumulatedWitchDamage[witchid];
			if (health < 0) health = 0;

			CPrintToChatAll("{default}[{olive}TS{default}]{green} Witch{default} had{default} %d health remaining.", health);
			CPrintToChatAll("{green}[提示]{lightgreen} %N {default}反被 {green}Witch {default}爆☆殺.", victim);
			g_iAccumulatedWitchDamage[witchid] = 0;
			g_bShouldAnnounceWitchDamage[witchid] = false;
			return Plugin_Continue;
		}
		
		if (GetConVarInt(cvarTank))
		{
			if ((victim != 0) && (attacker != 0))
			{
				if (GetClientTeam(victim) == 3 && GetClientTeam(attacker) != 3)
				{
					int class = GetEntProp(victim, Prop_Send, "m_zombieClass");
					if (class != ZOMBIECLASS_TANK)
					{
						return Plugin_Handled;
					}
				}
			}
		}
		//char Message[20];
		char MsgAssist[256];
		int TotalLeftDamage = 0;
		bool start = true;
		
		if ((victim != 0) && (attacker != 0))
		{
			if (GetClientTeam(victim) == 3 && GetClientTeam(attacker) != 3)
			{
				for (int i = 0; i <= MAXPLAYERS; i++)
				{
					if (Damage[i][victim] > 0)
					{
						if (i != attacker && IsClientConnected(i) && IsClientInGame(i))
						{
							if(start == false)
								StrCat(String:MsgAssist, sizeof(MsgAssist), String:Temp2);
							AssistFlag = true;
							char tName[MAX_NAME_LENGTH];
							GetClientName(i, tName, sizeof(tName));
							char tDamage[10];
							TotalLeftDamage += Damage[i][victim];
							IntToString(Damage[i][victim], String:tDamage, sizeof(tDamage));
							StrCat(String:MsgAssist, sizeof(MsgAssist), String:Temp5);
							StrCat(String:MsgAssist, sizeof(MsgAssist), String:tName);
							StrCat(String:MsgAssist, sizeof(MsgAssist), String:Temp6);
							StrCat(String:MsgAssist, sizeof(MsgAssist), String:Temp3);
							StrCat(String:MsgAssist, sizeof(MsgAssist), String:tDamage);
							StrCat(String:MsgAssist, sizeof(MsgAssist), String:Temp4);
							start=false;
						}
					}
				}
				PrintToChatAll("\x01[\x05TS\x01] \x04%N\x01 got killed by \x03%N\x01 (%d dmg).", victim, attacker,g_iTankCvarHealth - TotalLeftDamage);
				if (AssistFlag == true) 
				{
					PrintToChatAll("\x05\x01|| Assist: %s.",MsgAssist);
					AssistFlag = false;
				}
			}
		}
		for (int i = 0; i <= MAXPLAYERS; i++)
		{
			Damage[i][victim] = 0;
		}
	}
	return Plugin_Continue;
}

public void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast) 
{
	int witchid = GetEventInt(event, "witchid");
	g_bIsWitch[witchid] = true;
	g_iWitchidHealth[witchid] = g_iWitchHealth;
	g_bShouldAnnounceWitchDamage[witchid] = true;
}

public void Event_Witch_Death(Event event, const char[] name, bool dontBroadcast) 
{
	g_bIsWitch[GetEventInt(event, "witchid")] = false;
	g_bShouldAnnounceWitchDamage[GetEventInt(event, "witchid")] = true;
}

public void Event_Round_End(Event event, const char[] name, bool dontBroadcast) 
{
	if (GetConVarInt(cvarEnable))
	{
		for (int i = 0; i <= MAXPLAYERS; i++)
		{
			for (int a = 1; a <= MAXPLAYERS; a++)
			{
				Damage[i][a] = 0;
			}
		}
	}
}

public void OnConvarChange_TankHealth(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!StrEqual(oldValue, newValue))
		g_iTankCvarHealth = RoundFloat(g_hTankHealth.FloatValue * (IsVersusGameMode() ? 1.5 : GetCoopMultiplie()));
}

bool IsVersusGameMode()
{
	char sGameMode[12];
	GetConVarString(g_hGameMode, sGameMode, 12);
	return StrEqual(sGameMode, "versus");
}

float GetCoopMultiplie()
{
	char sDifficulty[24];
	GetConVarString(g_hDifficulty, sDifficulty, 24);

	if (StrEqual(sDifficulty, "Easy"))
		return 0.75;
	else if (StrEqual(sDifficulty, "Normal"))
		return 1.0;

	return 2.0;
}

bool IsTankDying(int tankclient)
{
	if (!tankclient) return false;
 
	return view_as<bool>(GetEntData(tankclient, g_iOffset_Incapacitated));
}