#include <sourcemod>
#include <colors>

#pragma semicolon 1

#define PLUGIN_VERSION "1.7"
#define ZOMBIECLASS_TANK 8

#define IsSurvivor(%0) (GetClientTeam(%0) == 2)
#define IsWitch(%0) (g_bIsWitch[%0])
#define MAXENTITIES 2048

new Handle:cvarEnable;
new Handle:cvarTank;

new bool:AssistFlag;

new Damage[MAXPLAYERS+1][MAXPLAYERS+1];
static g_iTankCvarHealth;
static		Handle:g_hTankHealth, Handle:g_hDifficulty, Handle:g_hGameMode;
//new String:Temp1[] = "|| Assist: ";
new String:Temp2[] = ", ";
new String:Temp3[] = " (";
new String:Temp4[] = " dmg)";
new String:Temp5[] = "\x05";
new String:Temp6[] = "\x01";
new		bool:	g_bIsWitch[MAXENTITIES];							// Membership testing for fast witch checking
new				g_iWitchidHealth[MAXENTITIES]								= 1000;	// Default
new 	g_iWitchHealth;
new				g_iAccumulatedWitchDamage[MAXENTITIES];							// Current witch health = witch health - accumulated
new		bool:	g_bShouldAnnounceWitchDamage[MAXENTITIES]				= false;
new     g_iOffset_Incapacitated     = 0;                // Used to check if tank is dying

public Plugin:myinfo = 
{
	name = "L4D Assistance System",
	author = "[E]c & Max Chu, SilverS & ViRaGisTe & Harry",
	description = "Show assists made by survivors",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=123811"
}

public OnPluginStart()
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
	
	g_iTankCvarHealth = RoundFloat(FloatMul(GetConVarFloat(g_hTankHealth), IsVersusGameMode() ? 1.5 : GetCoopMultiplie()));
	g_iOffset_Incapacitated = FindSendPropInfo("Tank", "m_isIncapacitated");
	
	HookConVarChange(g_hDifficulty,			OnConvarChange_TankHealth);
	HookConVarChange(g_hTankHealth,			OnConvarChange_TankHealth);
	HookConVarChange(g_hGameMode,			OnConvarChange_TankHealth);
	
	AutoExecConfig(true, "l4d2_assist");
}

public Event_InfectedHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (attacker == 0 ||								// Killed by world?
		!IsWitch(GetEventInt(event, "entityid")) ||		// Tracking witch damage only
		!IsClientInGame(attacker) ||
		!IsSurvivor(attacker)							// Claws
		) return;

	new damage = GetEventInt(event, "amount");
	g_iAccumulatedWitchDamage[GetEventInt(event, "entityid")] += damage;
}

public Action:Event_PlayerIncapacitated(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new witchid = GetEventInt(event, "attackerentid");
	if (!IsWitch(witchid)||
	!g_bShouldAnnounceWitchDamage[witchid]					// Prevent double print on witch incapping 2 players (rare)
	) return Plugin_Continue;

	if(victim<1 || victim > MaxClients || !IsClientConnected(victim) || !IsClientInGame(victim)) return Plugin_Continue;
	
	new health = g_iWitchidHealth[witchid] - g_iAccumulatedWitchDamage[witchid];
	if (health < 0) health = 0;
	
	CPrintToChatAll("{default}[{olive}TS{default}]{green} Witch{default} had{green} %d{default} health remaining.", health);
	CPrintToChatAll("{green}[提示]{lightgreen} %N {default}反被 {green}Witch {olive}爆☆殺{default}.", victim);
	
	g_iAccumulatedWitchDamage[witchid] = 0;
	g_bShouldAnnounceWitchDamage[witchid] = false;
	return Plugin_Continue;
}

public Action:Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_iWitchHealth = GetConVarInt(FindConVar("z_witch_health"));
	if (GetConVarInt(cvarEnable))
	{
		for (new i = 0; i <= MAXPLAYERS; i++)
		{
			for (new a = 1; a <= MAXPLAYERS; a++)
			{
				Damage[i][a] = 0;
			}
		}
	}
	ResetWitchTracking();
}

ResetWitchTracking()
{
	for (new i = MaxClients + 1; i < MAXENTITIES; i++) g_bIsWitch[i] = false;
}

public Action:Event_Player_Hurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarInt(cvarEnable))
	{
		new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		new victim = GetClientOfUserId(GetEventInt(event, "userid"));
		if (GetConVarInt(cvarTank))
		{
			new class = GetEntProp(victim, Prop_Send, "m_zombieClass");
			if (class != ZOMBIECLASS_TANK || IsTankDying(victim))
				return Plugin_Handled;
		}
		if ((victim != 0) && (attacker != 0))
		{
			if(GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 3 )
			{
				new DamageHealth = GetEventInt(event, "dmg_health");
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

public Action:Event_Player_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarInt(cvarEnable))
	{
		new victim = GetClientOfUserId(GetEventInt(event, "userid"));
		new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

		if (attacker == 0)
		{ // Check for a witch-related death (black & white survivor failing or no-incap configs e.g. 1v1)
			new witchid = GetEventInt(event, "attackerentid");
			if (!IsWitch(witchid)||
			!g_bShouldAnnounceWitchDamage[witchid]					// Prevent double print on witch incapping 2 players (rare)
			) return Plugin_Continue;
			
			if(victim<1 || victim > MaxClients || !IsClientConnected(victim) || !IsClientInGame(victim)) return Plugin_Continue;
			
			new health = g_iWitchidHealth[witchid] - g_iAccumulatedWitchDamage[witchid];
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
					new class = GetEntProp(victim, Prop_Send, "m_zombieClass");
					if (class != ZOMBIECLASS_TANK)
					{
						return Plugin_Handled;
					}
				}
			}
		}
		//new String:Message[20];
		new String:MsgAssist[256];
		new TotalLeftDamage = 0;
		new bool:start = true;
		
		if ((victim != 0) && (attacker != 0))
		{
			if (GetClientTeam(victim) == 3 && GetClientTeam(attacker) != 3)
			{
				//decl String:sName[MAX_NAME_LENGTH];
				//GetClientName(attacker, sName, sizeof(sName));
				//decl String:sDamage[10];
				//IntToString(Damage[attacker][victim], String:sDamage, sizeof(sDamage));
				//StrCat(String:Message, sizeof(Message), String:sName);
				//StrCat(String:Message, sizeof(Message), String:Temp6);
				//StrCat(String:Message, sizeof(Message), String:Temp3);
				//StrCat(String:Message, sizeof(Message), String:sDamage);
				//StrCat(String:Message, sizeof(Message), String:Temp4);

				for (new i = 0; i <= MAXPLAYERS; i++)
				{
					if (Damage[i][victim] > 0)
					{
						if (i != attacker && IsClientConnected(i) && IsClientInGame(i))
						{
							if(start == false)
								StrCat(String:MsgAssist, sizeof(MsgAssist), String:Temp2);
							AssistFlag = true;
							decl String:tName[MAX_NAME_LENGTH];
							GetClientName(i, tName, sizeof(tName));
							decl String:tDamage[10];
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
		for (new i = 0; i <= MAXPLAYERS; i++)
		{
			Damage[i][victim] = 0;
		}
	}
	return Plugin_Continue;
}

public Event_WitchSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new witchid = GetEventInt(event, "witchid");
	g_bIsWitch[witchid] = true;
	g_iWitchidHealth[witchid] = g_iWitchHealth;
	g_bShouldAnnounceWitchDamage[witchid] = true;
}

public Action:Event_Witch_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bIsWitch[GetEventInt(event, "witchid")] = false;
	g_bShouldAnnounceWitchDamage[GetEventInt(event, "witchid")] = true;
	return Plugin_Continue;
}

public Action:Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarInt(cvarEnable))
	{
		for (new i = 0; i <= MAXPLAYERS; i++)
		{
			for (new a = 1; a <= MAXPLAYERS; a++)
			{
				Damage[i][a] = 0;
			}
		}
	}
}

public OnConvarChange_TankHealth(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		g_iTankCvarHealth = RoundFloat(FloatMul(GetConVarFloat(g_hTankHealth), IsVersusGameMode() ? 1.5 : GetCoopMultiplie()));
}

bool:IsVersusGameMode()
{
	decl String:sGameMode[12];
	GetConVarString(g_hGameMode, sGameMode, 12);
	return StrEqual(sGameMode, "versus");
}

Float:GetCoopMultiplie()
{
	decl String:sDifficulty[24];
	GetConVarString(g_hDifficulty, sDifficulty, 24);

	if (StrEqual(sDifficulty, "Easy"))
		return 0.75;
	else if (StrEqual(sDifficulty, "Normal"))
		return 1.0;

	return 2.0;
}

bool:IsTankDying(tankclient)
{
	if (!tankclient) return false;
 
	return bool:GetEntData(tankclient, g_iOffset_Incapacitated);
}