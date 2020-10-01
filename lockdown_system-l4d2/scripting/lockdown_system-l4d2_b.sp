
#pragma semicolon 1
#pragma newdecls required //強制1.7以後的新語法
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <glow>
#include <left4dhooks>
#define PLUGIN_VERSION "3.3"

#define UNLOCK 0
#define LOCK 1
#define MODEL_TANK "models/infected/hulk.mdl"
#define MODEL_SAFEROOM_DOOR_1 "models/props_doors/checkpoint_door_02.mdl"
#define MODEL_SAFEROOM_DOOR_2 "models/props_doors/checkpoint_door_-02.mdl"
#define MODEL_SAFEROOM_DOOR_3 "models/lighthouse/checkpoint_door_lighthouse02.mdl"

ConVar lsAnnounce, lsAntiFarmDuration, lsDuration, lsMobs, lsTankDemolitionBefore, lsTankDemolitionAfter,
	lsType, lsNearByAllSurvivor, lsHint, lsGetInLimit, lsDoorOpeningTeleport, lsDoorOpeningTankInterval,
	lsDoorBotDisable, lsMapOff;

int iAntiFarmDuration, iDuration, iMobs, iType, iDoorStatus, iCheckpointDoor, iSystemTime, iGetInLimit, iDoorOpeningTankInterval;
int _iDoorOpeningTankInterval, g_iRoundStart, g_iPlayerSpawn;
float fDoorSpeed, fFirstUserOrigin[3];
bool bAntiFarmInit, bLockdownInit, bLDFinished, bAnnounce, 
	bNearByAllSurvivor,bDoorOpeningTeleport, bTankDemolitionBefore, bTankDemolitionAfter,
	bSurvivorsAssembleAlready,blsHint, bDoorBotDisable;
bool bSpawnTank, bRoundEnd;
char sKeyMan[128], sLastName[2048][128];
Handle hAntiFarmTime = null, hLockdownTime = null;
static Handle hCreateTank = null;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion evRetVal = GetEngineVersion();
	if (evRetVal != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "[TS] Plugin Supports L4D2 Only");
		return APLRes_SilentFailure;
	}

	CreateNative("Is_End_SafeRoom_Door_Open", Native_Is_End_SafeRoom_Door_Open);
	return APLRes_Success;
}

public int Native_Is_End_SafeRoom_Door_Open(Handle plugin, int numParams)
{
	return bLDFinished;
}

public Plugin myinfo = 
{
	name = "[L4D2] Lockdown System",
	author = "cravenge, Harry",
	description = "Locks Saferoom Door Until Someone Opens It.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/forumdisplay.php?f=108"
};

public void OnPluginStart()
{
	lsAnnounce = CreateConVar("lockdown_system-l4d2_announce", "1", "Enable/Disable Announcements", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsAntiFarmDuration = CreateConVar("lockdown_system-l4d2_anti-farm_duration", "50", "Duration Of Anti-Farm", FCVAR_NOTIFY);
	lsDuration = CreateConVar("lockdown_system-l4d2_duration", "100", "Duration Of Lockdown", FCVAR_NOTIFY);
	lsMobs = CreateConVar("lockdown_system-l4d2_mobs", "5", "Number Of Mobs To Spawn", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	lsTankDemolitionBefore = CreateConVar("lockdown_system-l4d2_tank_demolition_before", "1", "If 1, Enable Tank Demolition, server will spawn tank before door open ", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsTankDemolitionAfter = CreateConVar("lockdown_system-l4d2_tank_demolition_after", "1", "If 1, Enable Tank Demolition, server will spawn tank after door open ", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsType = CreateConVar("lockdown_system-l4d2_type", "2", "Lockdown Type: 0=Random, 1=Improved (opening slowly), 2=Default", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	lsNearByAllSurvivor = CreateConVar("lockdown_system-l4d2_all_survivors_near_saferoom", "1", "If 1, all survivors must assemble near the saferoom door before open.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsHint = CreateConVar(	"lockdown_system-l4d2_spam_hint", "1", "0=Off. 1=Display a message showing who opened or closed the saferoom door.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsGetInLimit = CreateConVar( "lockdown_system-l4d2_outside_slay_duration", "60", "After Safe room door is opened, slay players who are not inside saferoom in seconds. (0=off)", FCVAR_NOTIFY, true, 0.0);
	lsDoorOpeningTeleport = CreateConVar( "lockdown_system-l4d2_teleport", "1", "0=Off. 1=Teleport common, infected, and witch if they touch saferoom door from inside when door is opening. (prevent spawning and be stuck inside the saferoom)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsDoorOpeningTankInterval = CreateConVar( "lockdown_system-l4d2_opening_tank_interval", "30", "Time Interval to spawn a tank when door is opening (0=off)", FCVAR_NOTIFY, true, 0.0);
	lsDoorBotDisable = CreateConVar( "lockdown_system-l4d2_spam_bot_disable", "1", "If 1, prevent AI survivor from opening and closing the door.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	lsMapOff =	CreateConVar(	"lockdown_system-l4d2_map_off",		"c10m3_ranchhouse,l4d_reverse_hos03_sewers,l4d2_stadium4_city2,l4d_fairview10_church,l4d2_wanli01",				"Turn off the plugin in these maps, separate by commas (no spaces). (0=All maps, Empty = none).", FCVAR_NOTIFY );

	GetCvars();
	lsAnnounce.AddChangeHook(OnLSCVarsChanged);
	lsAntiFarmDuration.AddChangeHook(OnLSCVarsChanged);
	lsDuration.AddChangeHook(OnLSCVarsChanged);
	lsMobs.AddChangeHook(OnLSCVarsChanged);
	lsTankDemolitionBefore.AddChangeHook(OnLSCVarsChanged);
	lsTankDemolitionAfter.AddChangeHook(OnLSCVarsChanged);
	lsNearByAllSurvivor.AddChangeHook(OnLSCVarsChanged);
	lsHint.AddChangeHook(OnLSCVarsChanged);
	lsGetInLimit.AddChangeHook(OnLSCVarsChanged);
	lsDoorOpeningTeleport.AddChangeHook(OnLSCVarsChanged);
	lsDoorOpeningTankInterval.AddChangeHook(OnLSCVarsChanged);
	lsDoorBotDisable.AddChangeHook(OnLSCVarsChanged);

	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn,	EventHookMode_PostNoCopy);
	HookEvent("round_end", OnRoundEvents);
	HookEvent("mission_lost", OnRoundEvents); //wipe out
	HookEvent("map_transition", OnRoundEvents); //mission complete
	HookEvent("player_use", OnPlayerUsePre, EventHookMode_Pre);
	HookEvent("entity_killed", TC_ev_EntityKilled);
	HookEvent("door_open",			Event_DoorOpen);
	HookEvent("door_close",			Event_DoorClose);

	Handle hGameConf = LoadGameConfigFile("lockdown_system-l4d2");
	if( hGameConf == null )
	{
		SetFailState("Unable to find gamedata \"lockdown_system-l4d2\".");
	}
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "NextBotCreatePlayerBot<Tank>"))
		SetFailState("Unable to find NextBotCreatePlayerBot<Tank> signature in gamedata file.");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	hCreateTank = EndPrepSDKCall();
	if (hCreateTank == null)
		SetFailState("Cannot initialize NextBotCreatePlayerBot<Tank> SDKCall, signature is broken.") ;
	delete hGameConf;

	AutoExecConfig(true, "lockdown_system-l4d2");
}

public void OnLSCVarsChanged(ConVar cvar, const char[] sOldValue, const char[] sNewValue)
{
	GetCvars();
	
	if (IsValidEnt(iCheckpointDoor))
	{
		if (iType != 1)
		{
			return;
		}
		
		SetEntPropFloat(iCheckpointDoor, Prop_Data, "m_flSpeed", 89.0 / float(iDuration));
	}
}

public void OnPluginEnd()
{
	SetCheckpointDoor_Default();
	ResetPlugin();
}

bool g_bValidMap = true, g_bTwoSafeRoomDoorBug;
public void OnMapStart()
{
	g_bValidMap = true;
	g_bTwoSafeRoomDoorBug = false;

	char sCvar[512];
	lsMapOff.GetString(sCvar, sizeof(sCvar));

	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	if( sCvar[0] != '\0' )
	{
		if( strcmp(sCvar, "0") == 0 )
		{
			g_bValidMap = false;
		} else {
			Format(sMap, sizeof(sMap), ",%s,", sMap);
			Format(sCvar, sizeof(sCvar), ",%s,", sCvar);

			if( StrContains(sCvar, sMap, false) != -1 )
			{
				g_bValidMap = false;
			}
		}
	}

	if(L4D_IsMissionFinalMap())
	{
		g_bValidMap = false;
	}

	if (StrEqual(sMap, "c10m2_drainage", false))
	{
		g_bTwoSafeRoomDoorBug = true;
	}


	if (g_bValidMap)
	{
		PrecacheSound("doors/latchlocked2.wav", true);
		PrecacheSound("doors/door_squeek1.wav", true);	
		PrecacheSound("ambient/alarms/klaxon1.wav", true);
		PrecacheSound("level/highscore.wav", true);

		if (!IsModelPrecached(MODEL_TANK))
		{
			PrecacheModel(MODEL_TANK, true);
		}
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if( g_iPlayerSpawn == 1 && g_iRoundStart == 0 )
		CreateTimer(0.5, tmrStart, _, TIMER_FLAG_NO_MAPCHANGE);
	g_iRoundStart = 1;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if( g_iPlayerSpawn == 0 && g_iRoundStart == 1 )
		CreateTimer(0.5, tmrStart, _, TIMER_FLAG_NO_MAPCHANGE);
	g_iPlayerSpawn = 1;
}

public Action tmrStart(Handle timer)
{
	if (g_bValidMap == false)
	{
		return;
	}

	iType = (lsType.IntValue == 0) ? GetRandomInt(1, 2) : lsType.IntValue;
	
	bAntiFarmInit = false;
	bLockdownInit = false;
	bLDFinished = false;
	bSurvivorsAssembleAlready = false;
	bRoundEnd = false;
	bSpawnTank = false;
	_iDoorOpeningTankInterval = 0;

	InitDoor();

	ResetPlugin();
}


public Action TC_ev_EntityKilled(Event event, const char[] name, bool dontBroadcast) 
{
	if (g_bValidMap == false || !bTankDemolitionAfter || !bLDFinished)
	{
		return;
	}

	if (IsPlayerTank(event.GetInt("entindex_killed")))
	{
		CreateTimer(1.5, Timer_SpawnTank, _,TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_SpawnTank(Handle timer)
{
	if(RealFreePlayersOnInfected())
		CheatCommand(GetRandomClient(), "z_spawn_old", "tank auto");
	else
		ExecuteSpawn(true, 1);
}

public void OnRoundEvents(Event event, const char[] name, bool dontBroadcast)
{
	bRoundEnd = true;

	if (g_bValidMap == false)
	{
		return;
	}
	
	if (hAntiFarmTime != null)
	{
		if (!bLockdownInit)
		{
			bLockdownInit = true;
		}
		
		KillTimer(hAntiFarmTime);
		hAntiFarmTime = null;
		
		CreateTimer(1.75, ForceEndLockdown);
	}
	else
	{
		CreateTimer(1.5, ForceEndLockdown);
	}
	
	CreateTimer(2.0, OrderShutDown);

	ResetPlugin();
}

public Action ForceEndLockdown(Handle timer)
{
	if (hLockdownTime == null)
	{
		return Plugin_Stop;
	}
	
	if (!bLDFinished)
	{
		bLDFinished = true;
	}
	
	KillTimer(hLockdownTime);
	hLockdownTime = null;
	
	return Plugin_Stop;
}

public Action OrderShutDown(Handle timer)
{
	SetCheckpointDoor_Default();
	return Plugin_Stop;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if( g_bValidMap && bLDFinished && IsClientInGame(client) && GetClientTeam(client) == 2 && buttons & IN_USE)
	{
		if(IsFakeClient(client) && bDoorBotDisable) return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnPlayerUsePre(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bValidMap == false)
	{
		return Plugin_Continue;
	}
	
	int user = GetClientOfUserId(event.GetInt("userid"));
	if (IsSurvivor(user))
	{
		if (!IsPlayerAlive(user))
		{
			return Plugin_Continue;
		}
		if(bDoorBotDisable && IsFakeClient(user))
		{
			return Plugin_Continue;
		}
		
		int used = event.GetInt("targetid");
		if (IsValidEnt(used))
		{
			char sEntityClass[64];
			GetEdictClassname(used, sEntityClass, sizeof(sEntityClass));
			if (!StrEqual(sEntityClass, "prop_door_rotating_checkpoint") || used != iCheckpointDoor)
			{
				return Plugin_Continue;
			}
			
			if (iDoorStatus != UNLOCK)
			{
				if(bNearByAllSurvivor && !bSurvivorsAssembleAlready)
				{
					float clientOrigin[3];
					float doorOrigin[3];
					GetEntPropVector(used, Prop_Send, "m_vecOrigin", doorOrigin);
					for (int i = 1; i <= MaxClients; i++)
					{
						if(IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
						{
							GetClientAbsOrigin(i, clientOrigin);
							if (GetVectorDistance(clientOrigin, doorOrigin, true) > 850 * 850)
							{
								PrintHintText(user, "[TS] 所有倖存者必須集合才能打開安全門！");
								PrintCenterTextAll("[TS] 所有倖存者必須集合才能打開安全門！");
								return Plugin_Continue;
							}
						}
					}
					bSurvivorsAssembleAlready = true;
				}

				if(bTankDemolitionBefore && !bSpawnTank) 
				{
					ExecuteSpawn(true , 1);
					bSpawnTank = true;
				}
				
				if (GetTankCount() > 0)
				{
					if (bLDFinished || bLockdownInit)
					{
						bAntiFarmInit = true;
						return Plugin_Continue;
					}
					
					
					if (!bAntiFarmInit)
					{
						bAntiFarmInit = true;
						iSystemTime = iAntiFarmDuration;
						
						PrintHintText(user, "[TS] Tank還活著，請先殺了Tank！");
						EmitSoundToAll("doors/latchlocked2.wav", used, SNDCHAN_AUTO);

						GetClientAbsOrigin(user, fFirstUserOrigin);
						GetClientName(user, sKeyMan, sizeof(sKeyMan));
						
						ExecuteSpawn(false, iMobs);
						
						if (hAntiFarmTime == null)
						{
							hAntiFarmTime = CreateTimer(float(iAntiFarmDuration) + 1.0, EndAntiFarm);
						}
						CreateTimer(1.0, CheckAntiFarm, used, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
						SDKHook(used, SDKHook_Touch, OnTouch);
					}
				}
				else
				{
					if (bAntiFarmInit)
					{
						return Plugin_Continue;
					}
					
					if (!bLockdownInit)
					{
						bLockdownInit = true;
						iSystemTime = iDuration;

						GetClientAbsOrigin(user, fFirstUserOrigin);
						GetClientName(user, sKeyMan, sizeof(sKeyMan));
						
						ExecuteSpawn(false, iMobs);
						if (iType == 1)
						{
							ControlDoor(iCheckpointDoor, UNLOCK);
						}
						
						if (hLockdownTime == null)
						{
							hLockdownTime = CreateTimer(float(iDuration) + 1.0, EndLockdown);
						}

						CreateTimer(1.0, LockdownOpening, used, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
						SDKHook(used, SDKHook_Touch, OnTouch);
					}
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action CheckAntiFarm(Handle timer, any entity)
{
	if (GetTankCount() < 1 || hAntiFarmTime == null)
	{
		if (hAntiFarmTime != null)
		{
			KillTimer(hAntiFarmTime);
			hAntiFarmTime = null;
		}
		
		if (!bLockdownInit)
		{
			bLockdownInit = true;
			ExecuteSpawn(false, iMobs);
			
			if (iType == 1)
			{
				ControlDoor(iCheckpointDoor, UNLOCK);
			}
			
			if (hLockdownTime == null)
			{
				hLockdownTime = CreateTimer(float(iDuration) + 1.0, EndLockdown);
			}
			iSystemTime = iDuration;
			CreateTimer(1.0, LockdownOpening, entity, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
		return Plugin_Stop;
	}
	
	PrintCenterTextAll("[ANTI-FARM] Tank還活著，請先殺了Tank！\n否則等待 %d 秒!", iSystemTime);
	iSystemTime -= 1;
	
	return Plugin_Continue;
}

public Action EndAntiFarm(Handle timer)
{
	if (hAntiFarmTime == null)
	{
		return Plugin_Stop;
	}
	
	KillTimer(hAntiFarmTime);
	hAntiFarmTime = null;
	
	return Plugin_Stop;
}

public Action LockdownOpening(Handle timer, any entity)
{
	if (hLockdownTime == null)
	{
		if (!bLDFinished)
		{
			bLDFinished = true;
			
			EmitSoundToAll("doors/door_squeek1.wav", entity);
			if (iType != 1)
			{
				ControlDoor(entity, UNLOCK);
			}
			else
			{
				SetEntPropFloat(entity, Prop_Data, "m_flSpeed", fDoorSpeed);
			}
			
			EmitSoundToAll("level/highscore.wav", entity, SNDCHAN_AUTO, SNDLEVEL_RAIDSIREN, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_LOW, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
			PrintCenterTextAll("安全門已開啟!! 大家趕快進去!!");
			
			if (bAnnounce)
			{
				PrintToChatAll("\x01[\x05TS\x01]\x04 <\x05%s\x04>\x01 打開了 安全室大門!", sKeyMan);
			}
			
			CreateTimer(5.0, LaunchTankDemolition);
			CreateTimer(5.0, LaunchSlayTimer, entity);
		}
		return Plugin_Stop;
	}
	
	EmitSoundToAll("ambient/alarms/klaxon1.wav", entity, SNDCHAN_AUTO, SNDLEVEL_RAIDSIREN, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_LOW, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	PrintCenterTextAll("[LOCKDOWN] 開門倒數 %d 秒!", iSystemTime);
	iSystemTime -= 1;

	if(iDoorOpeningTankInterval > 0 && _iDoorOpeningTankInterval >= iDoorOpeningTankInterval)
	{
		CreateTimer(0.1, Timer_SpawnTank, _,TIMER_FLAG_NO_MAPCHANGE);
		_iDoorOpeningTankInterval = 0;
	}
	_iDoorOpeningTankInterval++;

	return Plugin_Continue;
}

public Action EndLockdown(Handle timer)
{
	if (hLockdownTime == null)
	{
		return Plugin_Stop;
	}
	
	KillTimer(hLockdownTime);
	hLockdownTime = null;
	
	return Plugin_Stop;
}

public Action LaunchTankDemolition(Handle timer)
{
	if (bTankDemolitionAfter == false)
	{
		return Plugin_Stop;
	}
	
	ExecuteSpawn(true, 4);
	if (bAnnounce)
	{
		PrintToChatAll("\x01[\x05TS\x01]\x01 \x04Tank \x01大軍壓境!!");
	}
	
	return Plugin_Stop;
}

public Action LaunchSlayTimer(Handle timer, any entity)
{
	iSystemTime = iGetInLimit;
	CreateTimer(1.0, AntiPussy, entity, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action AntiPussy(Handle timer, any entity)
{
	if(bRoundEnd) return Plugin_Stop;
	
	EmitSoundToAll("ambient/alarms/klaxon1.wav", entity, SNDCHAN_AUTO, SNDLEVEL_RAIDSIREN, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_LOW, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	PrintCenterTextAll("[LOCKDOWN] 安全室門外死亡倒數 %d 秒!", iSystemTime);
	
	if(iSystemTime <= 0)
	{
		PrintToChatAll("\x01[\x05TS\x01]\x05 安全室門外區域的玩家將處以死刑!");
		CreateTimer(1.0, _AntiPussy, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}

	iSystemTime -= 1;
	return Plugin_Continue;
}

public Action _AntiPussy(Handle timer)
{
	if(bRoundEnd) return Plugin_Stop;
	
	for( int i = 1; i <= MaxClients; i++ ) 
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !L4D_IsInLastCheckpoint(i))
		{
			ForcePlayerSuicide(i);
			PrintHintText(i, "[TS] 你位於安全門外，處以死刑！！");
			PrintToChatAll("\x01[\x05TS\x01]\x04 <\x05%N\x04>\x01 位於安全室門外，已被處死!", i);
		}
	}
	return Plugin_Continue;
}

public void OnMapEnd()
{
	bAntiFarmInit = false;
	bLockdownInit = false;
	bLDFinished = false;
	
	SetCheckpointDoor_Default();

	ResetPlugin();
}

void InitDoor()
{
	if (IsValidEnt(iCheckpointDoor))
	{
		return;
	}
	
	int iCheckpointEnt = -1;
	while ((iCheckpointEnt = FindEntityByClassname(iCheckpointEnt, "prop_door_rotating_checkpoint")) != -1)
	{
		if (!IsValidEntity(iCheckpointEnt) || !IsValidEdict(iCheckpointEnt))
		{
			continue;
		}
		
		char sEntityName[128];
		GetEntPropString(iCheckpointEnt, Prop_Data, "m_iName", sEntityName, sizeof(sEntityName));
		if (StrEqual(sEntityName, "checkpoint_entrance", false))
		{
			if (sLastName[iCheckpointEnt][0] != '\0')
			{
				DispatchKeyValue(iCheckpointEnt, "targetname", sLastName[iCheckpointEnt]);
				sLastName[iCheckpointEnt][0] = '\0';
			}
			
			fDoorSpeed = GetEntPropFloat(iCheckpointEnt, Prop_Data, "m_flSpeed");
			
			ControlDoor(iCheckpointEnt, LOCK);
			
			HookSingleEntityOutput(iCheckpointEnt, "OnFullyOpen", OnDoorAntiSpam);
			HookSingleEntityOutput(iCheckpointEnt, "OnFullyClosed", OnDoorAntiSpam);
			
			HookSingleEntityOutput(iCheckpointEnt, "OnBlockedOpening", OnDoorBlocked);
			HookSingleEntityOutput(iCheckpointEnt, "OnBlockedClosing", OnDoorBlocked);
			
			iCheckpointDoor = iCheckpointEnt;

			break;
		}
		else if (g_bTwoSafeRoomDoorBug == false)
		{
			char sEntityModel[128];
			GetEntPropString(iCheckpointEnt, Prop_Data, "m_ModelName", sEntityModel, sizeof(sEntityModel));
			if ( StrEqual(sEntityModel, MODEL_SAFEROOM_DOOR_1, false) || StrEqual(sEntityModel, MODEL_SAFEROOM_DOOR_2, false) || StrEqual(sEntityModel, MODEL_SAFEROOM_DOOR_3, false))
			{
				if (sEntityName[0] != '\0')
				{
					strcopy(sLastName[iCheckpointEnt], 128, sEntityName);
				}
				DispatchKeyValue(iCheckpointEnt, "targetname", "checkpoint_entrance");
				
				InitDoor();
				break;
			}
		}
	}
}

public void OnDoorAntiSpam(const char[] output, int caller, int activator, float delay)
{
	if (StrEqual(output, "OnFullyClosed") && !bLDFinished)
	{
		return;
	}
	
	AcceptEntityInput(caller, "Lock");
	SetEntProp(caller, Prop_Data, "m_hasUnlockSequence", LOCK);
	
	L4D2_SetEntGlow(caller, L4D2Glow_Constant, 550, 0, {0, 0, 255}, false);
	
	CreateTimer(3.0, PreventDoorSpam, EntIndexToEntRef(caller));
}

public Action PreventDoorSpam(Handle timer, any entity)
{
	if ((entity = EntRefToEntIndex(entity)) == INVALID_ENT_REFERENCE)
	{
		return Plugin_Stop;
	}
	
	L4D2_SetEntGlow(entity, L4D2Glow_Constant, 550, 0, {255, 255, 0}, false);
	
	SetEntProp(entity, Prop_Data, "m_hasUnlockSequence", UNLOCK);
	AcceptEntityInput(entity, "Unlock");
	
	return Plugin_Stop;
}

public void OnDoorBlocked(const char[] output, int caller, int activator, float delay)
{
	//PrintToChatAll("OnDoorBlockeding caller:%d, activator: %d, output: %s",caller,activator,output);
	if (!IsCommonInfected(activator))
	{
		return;
	}

	AcceptEntityInput(activator, "BecomeRagdoll");
}

void ControlDoor(int entity, int iOperation)
{
	iDoorStatus = iOperation;
	
	switch (iOperation)
	{
		case LOCK:
		{
			L4D2_SetEntGlow(entity, L4D2Glow_Constant, 550, 0, {0, 0, 255}, false);
			
			AcceptEntityInput(entity, "Close");
			if (iType == 1)
			{
				SetEntPropFloat(entity, Prop_Data, "m_flSpeed", 89.0 / float(iDuration));
			}
			AcceptEntityInput(entity, "Lock");
			if (iType != 1)
			{
				AcceptEntityInput(entity, "ForceClosed");
			}
			SetEntProp(entity, Prop_Data, "m_hasUnlockSequence", LOCK);
		}
		case UNLOCK:
		{
			L4D2_SetEntGlow(entity, L4D2Glow_Constant, 550, 0, {255, 255, 0}, false);
			
			SetEntProp(entity, Prop_Data, "m_hasUnlockSequence", UNLOCK);
			AcceptEntityInput(entity, "Unlock");
			AcceptEntityInput(entity, "ForceClosed");
			AcceptEntityInput(entity, "Open");
		}
	}
}

int GetRandomClient()
{
	int iClientCount, iClients[MAXPLAYERS+1];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			iClients[iClientCount++] = i;
		}
	}
	return (iClientCount == 0) ? 0 : iClients[GetRandomInt(0, iClientCount - 1)];
}

int GetTankCount()
{
	int iCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_zombieClass") == 8 && IsPlayerAlive(i))
		{
			iCount += 1;
		}
	}
	return iCount;
}

stock bool IsSurvivor(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}

stock bool IsValidEnt(int entity)
{
	return (entity > 0 && IsValidEntity(entity) && IsValidEdict(entity));
}

stock bool IsCommonInfected(int entity)
{
	if (IsValidEnt(entity))
	{
		char sEntityClass[64];
		GetEdictClassname(entity, sEntityClass, sizeof(sEntityClass));
		return StrEqual(sEntityClass, "infected");
	}
	
	return false;
}

stock void ExecuteSpawn(bool btank, int iCount)
{
	if (btank)
	{
		CreateTankBot();
		iCount--;
		for (int i = 1; i <= iCount; i++)
		{
			CreateTimer(0.5 * i, Timer_CreateTank);
		}
	}
	else
	{
		int anyclient = GetRandomClient();
		if(anyclient > 0)
		{
			for (int i = 0; i < iCount; i++)
			{
				FakeClientCommand(anyclient, "z_spawn mob auto");
			}
		}	
	}
}

public Action Timer_CreateTank(Handle timer)
{
	CreateTankBot();	
}

void CreateTankBot()
{
	float vecPos[3];
	int anyclient = GetRandomClient();
	if(anyclient > 0 && L4D_GetRandomPZSpawnPosition(anyclient,8,5,vecPos) == true)
	{
		int newtankbot = SDKCall(hCreateTank, "Lock Down Tank Bot"); //召喚坦克
		if (newtankbot > 0 && IsValidClient(newtankbot))
		{
			SetEntityModel(newtankbot, MODEL_TANK);
			ChangeClientTeam(newtankbot, 3);
			SetEntProp(newtankbot, Prop_Send, "m_usSolidFlags", 16);
			SetEntProp(newtankbot, Prop_Send, "movetype", 2);
			SetEntProp(newtankbot, Prop_Send, "deadflag", 0);
			SetEntProp(newtankbot, Prop_Send, "m_lifeState", 0);
			SetEntProp(newtankbot, Prop_Send, "m_iObserverMode", 0);
			SetEntProp(newtankbot, Prop_Send, "m_iPlayerState", 0);
			SetEntProp(newtankbot, Prop_Send, "m_zombieState", 0);
			DispatchSpawn(newtankbot);
			ActivateEntity(newtankbot);
			TeleportEntity(newtankbot, vecPos, NULL_VECTOR, NULL_VECTOR); //移動到相同位置
		}
	}
}

stock bool IsPlayerGhost(int client)
{
	if (GetEntProp(client, Prop_Send, "m_isGhost", 1)) return true;
	return false;
}

bool IsValidClient(int client, bool replaycheck = true)
{
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	//if (GetEntProp(client, Prop_Send, "m_bIsCoaching")) return false;
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	}
	return true;
}

stock void CheatCommand(int client,  char[] command, char[] arguments = "")
{
	if(client == 0) return;
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
}

bool RealFreePlayersOnInfected ()
{
	for (int i=1;i<=MaxClients;i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 3 && (IsPlayerGhost(i) || !IsPlayerAlive(i)))
			return true;
	}
	return false;
}

bool IsPlayerTank (int client)
{
    return (GetEntProp(client, Prop_Send, "m_zombieClass") == 8);
}

public void Event_DoorOpen(Event event, const char[] name, bool dontBroadcast)
{
	if( event.GetBool("checkpoint") )
		DoorPrint(event, true);
}

public void Event_DoorClose(Event event, const char[] name, bool dontBroadcast)
{
	if( event.GetBool("checkpoint") )
		DoorPrint(event, false);
}

void DoorPrint(Event event, bool open)
{
	if( bLDFinished && blsHint)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if( client && IsClientInGame(client) && GetClientTeam(client) == 2)
		{
			if(open) PrintToChatAll("\x01[\x05TS\x01]\x04 ---\x05%N\x04---\x01 打開 安全門!", client);
			else PrintToChatAll("\x01[\x05TS\x01]\x04 ---\x05%N\x04---\x01 關閉 安全門!", client);
		}
	}
}

void GetCvars()
{
	iAntiFarmDuration = lsAntiFarmDuration.IntValue;
	iDuration = lsDuration.IntValue;
	iMobs = lsMobs.IntValue;
	
	bAnnounce = lsAnnounce.BoolValue;
	bTankDemolitionBefore = lsTankDemolitionBefore.BoolValue;
	bTankDemolitionAfter = lsTankDemolitionAfter.BoolValue;
	bNearByAllSurvivor = lsNearByAllSurvivor.BoolValue;
	blsHint = lsHint.BoolValue;
	iGetInLimit = lsGetInLimit.IntValue;
	bDoorOpeningTeleport = lsDoorOpeningTeleport.BoolValue;
	iDoorOpeningTankInterval = lsDoorOpeningTankInterval.IntValue;
	bDoorBotDisable = lsDoorBotDisable.BoolValue;
}

public void OnTouch(int door, int other)
{
	if(!bDoorOpeningTeleport) return;

	if(bRoundEnd || bLDFinished)
	{
		SDKUnhook(door, SDKHook_Touch, OnTouch);
	}
	//PrintToChatAll("%d touches door %d",other,door);

	if (IsValidClient(other) && GetClientTeam(other) == 3 && L4D_IsInLastCheckpoint(other))
	{
		TeleportEntity(other, fFirstUserOrigin, NULL_VECTOR, NULL_VECTOR);
		return;
	}

	if (IsCommonInfected(other))
	{
		TeleportEntity(other, fFirstUserOrigin, NULL_VECTOR, NULL_VECTOR);
		return;
	}

	if (IsWitch(other))
	{
		TeleportEntity(other, fFirstUserOrigin, NULL_VECTOR, NULL_VECTOR);
		return;
	}
}

bool IsWitch(int entity)
{
    if (entity > 0 && IsValidEntity(entity) && IsValidEdict(entity))
    {
        char strClassName[64];
        GetEdictClassname(entity, strClassName, sizeof(strClassName));
        return StrEqual(strClassName, "witch");
    }
    return false;
}

void ResetPlugin()
{
	g_iRoundStart = 0;
	g_iPlayerSpawn = 0;
}

void SetCheckpointDoor_Default()
{
	if (iCheckpointDoor != 0)
	{
		if (IsValidEntity(iCheckpointDoor) && IsValidEdict(iCheckpointDoor))
		{
			L4D2_SetEntGlow(iCheckpointDoor, L4D2Glow_None, 0, 0, {0, 0, 0}, false);
			
			UnhookSingleEntityOutput(iCheckpointDoor, "OnFullyOpen", OnDoorAntiSpam);
			UnhookSingleEntityOutput(iCheckpointDoor, "OnFullyClosed", OnDoorAntiSpam);
			
			UnhookSingleEntityOutput(iCheckpointDoor, "OnBlockedOpening", OnDoorBlocked);
			UnhookSingleEntityOutput(iCheckpointDoor, "OnBlockedClosing", OnDoorBlocked);

			if (iType == 1)
			{
				SetEntPropFloat(iCheckpointDoor, Prop_Data, "m_flSpeed", fDoorSpeed);
			}
			
			iDoorStatus = UNLOCK;
		}
		
		iCheckpointDoor = 0;
	}
}