#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <multicolors>

#pragma newdecls required

#define LOGO "[{orange}MUSIC{default}]"
#define PLUGIN_VERSION "1.0.0"

Database db;

ConVar cvar_url;

bool do_search[MAXPLAYERS + 1] = false;
bool set_volume[MAXPLAYERS + 1] = false;
bool create_playlist[MAXPLAYERS + 1] = false;
bool yt_motd[MAXPLAYERS + 1] = false;
bool yt_login[MAXPLAYERS + 1] = false;
bool player_menu[MAXPLAYERS + 1] = false;
bool late_load = false;

char steamid[MAXPLAYERS + 1][34];
char selected_song[MAXPLAYERS + 1][555];
char search_arg[MAXPLAYERS + 1];
char motd_url[MAXPLAYERS + 1][555];

#include "ytmusic/list.sp"
#include "ytmusic/playlist.sp"
#include "ytmusic/sql.sp"

public Plugin myinfo =  {
	name = "Youtube Music Player", 
	author = "TINTINTINTINTIN BATGIRL  TINTINTINTINTIN", 
	description = "youtube for sourcemod", 
	version = PLUGIN_VERSION, 
	url = ""
};

public APLRes APLResAskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max) {
	late_load = bLate;
	return APLRes_Success;
}

public void OnPluginStart() {
	RegConsoleCmd("sm_music", cmd_music);
	RegConsoleCmd("sm_mplay", cmd_play);
	RegConsoleCmd("sm_mpause", cmd_pause);
	RegConsoleCmd("sm_mstop", cmd_stop);
	RegConsoleCmd("sm_mnext", cmd_next);
	RegConsoleCmd("sm_mprevious", cmd_previous);
	RegConsoleCmd("sm_vstop", cmd_vstop);
	
	AddCommandListener(Say, "say_team");
	AddCommandListener(Say, "say");
	
	cvar_url = CreateConVar("website_url", "http://mywebsite.com/ytmusic/", "Website url");
	AutoExecConfig(true, "music");
	
	if (late_load) {
		for (int i = MaxClients; i > 0; i--)
			OnClientPutInServer(i);
	}
	
	DBConnect();
	LoadTranslations("music.phrases");
}

public void OnClientPutInServer(int client) {
	if (client <= 0 || IsFakeClient(client) || !IsClientInGame(client))
		return;
	
	do_search[client] = false;
	set_volume[client] = false;
	create_playlist[client] = false;
	yt_motd[client] = false;
	yt_login[client] = false;
	player_menu[client] = false;
	
	GetClientAuthId(client, AuthId_Steam2, steamid[client], sizeof(steamid));
	client_connect(client);
}

public void OnClientDisconnect(int client) {
	if (client <= 0 || IsFakeClient(client) || !IsClientInGame(client))
		return;
	
	char sql[364];
	do_search[client] = false;
	set_volume[client] = false;
	create_playlist[client] = false;
	yt_motd[client] = false;
	yt_login[client] = false;
	player_menu[client] = false;
	
	Format(sql, sizeof(sql), "DELETE FROM youtube WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	Format(sql, sizeof(sql), "UPDATE youtube_user SET etat = '0', isplayed = NULL, playlist_id = '-1', playlist_index = '-1', action = '0', url = NULL WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
}

void IndexMenu(int client) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT volume FROM youtube_user WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, IndexMenuCallback, sql, client);
}

public void IndexMenuCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char translations[555];
	int client = data;
	
	if (hndl == null) {
		LogError("Query failed(IndexMenuCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
		
	int volumee = SQL_FetchInt(hndl, 0);
	
	Menu menu = new Menu(MenuIndexMusic);
	menu.SetTitle("%t", "menu title");
	
	Format(translations, sizeof(translations), "%t", "menu item player");
	menu.AddItem("player", translations);
	
	Format(translations, sizeof(translations), "%t", "menu item music");
	menu.AddItem("music", translations);
	
	Format(translations, sizeof(translations), "%t", "menu volume", volumee);
	menu.AddItem("volume", translations);
	
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuIndexMusic(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if (StrEqual(choice, "player")) {
				PlayerMenu(param1);
			} else if (StrEqual(choice, "music")) {
				MainMenu(param1);
			} else if (StrEqual(choice, "volume")) {
				CPrintToChat(param1, "%t", "set volume", LOGO);
				set_volume[param1] = true;
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void PlayerMenu(int client) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT isplayed, etat, volume, playlist_id FROM youtube_user WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, PlayerMenuCallback, sql, client);
}

public void PlayerMenuCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char isplayed[555];
	char sql[364];
	int client = data;
	
	if (hndl == null) {
		LogError("Query failed(PlayerMenuCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	SQL_FetchString(hndl, 0, isplayed, sizeof(isplayed));
	int status = SQL_FetchInt(hndl, 1);
	int pid = SQL_FetchInt(hndl, 3);
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(isplayed);
	pack.WriteCell(status);
	pack.WriteCell(pid);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT * FROM youtube_playlist_music WHERE id = '%i'", pid);
	SQL_TQuery(db, PlayerMenuSelectCallback, sql, pack);
}

public void PlayerMenuSelectCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char isplayed[555];
	char translation[364];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(isplayed, sizeof(isplayed));
	int status = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(PlayerMenuSelectCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	Menu menu = new Menu(PlayerMusic, MenuAction_DrawItem);
	menu.SetTitle("%t", "menu title");
	
	if (status == 0)
		Format(translation, sizeof(translation), "%t", "menu no music played");
	else if (status == 2)
		Format(translation, sizeof(translation), "%t", "menu paused", isplayed);
	else if (status == 1)
		Format(translation, sizeof(translation), "%t", "menu played", isplayed);
	menu.AddItem("disabled", translation);
	
	if (status == 2) {
		Format(translation, sizeof(translation), "%t", "menu item play");
		menu.AddItem("play", translation);
	} else if (status == 1) {
		Format(translation, sizeof(translation), "%t", "menu item pause");
		menu.AddItem("pause", translation);
	} else {
		Format(translation, sizeof(translation), "%t/%t", "menu item play", "menu item pause");
		menu.AddItem("disabled", translation);
	}
	
	if (status != 0) {
		Format(translation, sizeof(translation), "%t", "menu item stop");
		menu.AddItem("stop", translation);
		
		Format(translation, sizeof(translation), "%t", "menu item add playlist");
		menu.AddItem("addp", translation);
	} else {
		Format(translation, sizeof(translation), "%t", "menu item stop");
		menu.AddItem("disabled", translation);
	}
	
	if (SQL_GetRowCount(hndl) > 1) {
		Format(translation, sizeof(translation), "%t", "menu item next");
		menu.AddItem("next", translation);
		
		Format(translation, sizeof(translation), "%t", "menu item previous");
		menu.AddItem("previous", translation);
	}
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PlayerMusic(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DrawItem:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if (StrEqual(choice, "disabled"))
				return ITEMDRAW_DISABLED;
		}
		case MenuAction_Select:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if (StrEqual(choice, "play"))
				FakeClientCommand(param1, "sm_mplay");
			else if (StrEqual(choice, "pause"))
				FakeClientCommand(param1, "sm_mpause");
			else if (StrEqual(choice, "stop"))
				FakeClientCommand(param1, "sm_mstop");
			else if (StrEqual(choice, "next"))
				FakeClientCommand(param1, "sm_mnext");
			else if (StrEqual(choice, "previous"))
				FakeClientCommand(param1, "sm_mprevious");
			else if (StrEqual(choice, "addp")) {
				player_menu[param1] = true;
				char sql[555];
				Format(sql, sizeof(sql), "SELECT isplayed, url FROM youtube_user WHERE steamid = '%s'", steamid[param1]);
				SQL_TQuery(db, MenuPlayerAddPlaylistCallback, sql, param1);
			}
			PlayerMenu(param1);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				IndexMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public void MenuPlayerAddPlaylistCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	char name[555];
	char url[555];
	
	if (hndl == null) {
		LogError("Query failed(MenuPlayerAddPlaylistCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
		
	SQL_FetchString(hndl, 0, name, sizeof(name));
	SQL_FetchString(hndl, 1, url, sizeof(url));
	add_playlist_menu(client, name, url);
}

void MainMenu(int client) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT * FROM youtube_playlist WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, MainMenuCallback, sql, client);
}

public void MainMenuCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	bool HavePlaylist = false;
	char translations[555];
	
	if (hndl == null) {
		LogError("Query failed(MainMenuCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (SQL_GetRowCount(hndl) != 0) {
		HavePlaylist = true;
	}
	
	Menu menu = new Menu(MenuMainMusic, MenuAction_DrawItem);
	menu.SetTitle("%t", "menu title");
	
	Format(translations, sizeof(translations), "%t", "menu item search");
	menu.AddItem("search", translations);
	
	Format(translations, sizeof(translations), "%t", "menu item playlist");
	if (HavePlaylist)
		menu.AddItem("playlist", translations);
	else
		menu.AddItem("disabled", translations);
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuMainMusic(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DrawItem:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if (StrEqual(choice, "disabled"))
				return ITEMDRAW_DISABLED;
		}
		case MenuAction_Select:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if (StrEqual(choice, "search")) {
				CPrintToChat(param1, "%t", "do search", LOGO);
				do_search[param1] = true;
			} else if (StrEqual(choice, "playlist")) {
				MainPlaylistMenu(param1);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				IndexMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public int MenuMusic(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DrawItem:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if (StrEqual(choice, "disabled"))
				return ITEMDRAW_DISABLED;
		}
		case MenuAction_Select:
		{
			char choice[248];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			
			if(StrEqual(choice, "new")) {
				CPrintToChat(param1, "%t", "do search", LOGO);
				do_search[param1] = true;
			} else {
				exec_menu(param1, choice);
				Format(selected_song[param1], sizeof(selected_song), "%s", choice);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				MainMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void exec_menu(int client, char[] choice) {
	char yt_menu_play[124];
	char translations[124];
	char yt_menu_playlist[124];
	
	Menu menu = new Menu(MenuExecMusic);
	menu.SetTitle("%t", "menu title");
	
	Format(yt_menu_play, sizeof(yt_menu_play), "%s|play", choice);
	Format(translations, sizeof(translations), "%t", "menu item play");
	menu.AddItem(yt_menu_play, translations);
	
	Format(yt_menu_playlist, sizeof(yt_menu_playlist), "%s|playlist", choice);
	Format(translations, sizeof(translations), "%t", "menu item add playlist");
	menu.AddItem(yt_menu_playlist, translations);
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuExecMusic(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select:
		{
			char choice[555];
			char explode_choice[10][999];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			ExplodeString(choice, "|", explode_choice, sizeof(explode_choice[]), sizeof(explode_choice[]));
			
			if (StrEqual(explode_choice[2], "play")) {
				update_video(param1, explode_choice[0], explode_choice[1]);
				PlayerMenu(param1);
			} else if (StrEqual(explode_choice[2], "playlist")) {
				add_playlist_menu(param1, explode_choice[0], explode_choice[1]);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				search_result_menu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public Action Say(int client, char[] command, int args) {
	if (client <= 0 || IsFakeClient(client) || !IsClientInGame(client))
		return Plugin_Handled;
	
	char sql[555];
	char arg[555];
	GetCmdArgString(arg, sizeof(arg));
	ReplaceString(arg, sizeof(arg), "\"", "");
	
	if (do_search[client] == true) {
		search_list(client, arg, sizeof(arg));
		return Plugin_Handled;
	}
	if (create_playlist[client] == true) {
		playlist_created(client, arg, sizeof(arg));
		return Plugin_Handled;
	}
	if (set_volume[client] == true) {
		int vol = StringToInt(arg);
		if(vol <= 0)
			vol = 0;
		if (vol >= 100)
			vol = 100;
			
		Format(sql, sizeof(sql), "UPDATE youtube_user SET volume = '%i' WHERE steamid = '%s'", vol, steamid[client]);
		SQL_TQuery(db, SQLCallback, sql, client);
		CPrintToChat(client, "%t", "volume", LOGO, vol);
		IndexMenu(client);
		set_volume[client] = false;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action cmd_music(int client, int args) {
	if(args > 0) {
		char arg[555];
		GetCmdArgString(arg, sizeof(arg));
		search_list(client, arg, sizeof(arg));
	} 
	else
		IndexMenu(client);
}

public Action cmd_vstop(int client, int args) {
	set_volume[client] = false;
}

public Action cmd_stop(int client, int args) {
	char sql[364];
	Format(sql, sizeof(sql), "UPDATE youtube_user SET etat = '0', isplayed = NULL, url = NULL, playlist_id = '-1', playlist_index = '-1' WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	CreateTimer(3.0, stopmotd, client);
}

public Action stopmotd(Handle Timer, int client) {
	motd(client, "about:blank");
	yt_motd[client] = false;
}

public Action cmd_play(int client, int args) {
	char sql[364];
	Format(sql, sizeof(sql), "UPDATE youtube_user SET etat = '1' WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	PlayerMenu(client);
}

public Action cmd_pause(int client, int args) {
	char sql[364];
	Format(sql, sizeof(sql), "UPDATE youtube_user SET etat = '2' WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	PlayerMenu(client);
}

public Action cmd_next(int client, int args) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT playlist_id, playlist_index FROM youtube_user WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, NextCallback, sql, client);
}

public void NextCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	char sql[555];
	
	if (hndl == null) {
		LogError("Query failed(NextCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
		
	int pid = SQL_FetchInt(hndl, 0);
	int index = SQL_FetchInt(hndl, 1);
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(index);
	pack.WriteCell(pid);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT MAX(`index`) FROM youtube_playlist_music WHERE id = '%i'", pid);
	SQL_TQuery(db, Next2Callback, sql, pack);
}

public void Next2Callback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	int index = pack.ReadCell();
	int pid = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(Next2Callback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	int max_index = SQL_FetchInt(hndl, 0);
	index = index + 1;
	if(max_index < index)
		index = 0;
		
	pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(index);
	pack.WriteCell(pid);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT name, url FROM youtube_playlist_music WHERE id = '%i' AND `index` = '%i'", pid, index);
	SQL_TQuery(db, GetSoundInfoNextCallback, sql, pack);
}

public void GetSoundInfoNextCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char name[364];
	char url[364];
	char sql[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	int index = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(GetSoundInfoNextCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	SQL_FetchString(hndl, 0, name, sizeof(name));
	SQL_FetchString(hndl, 1, url, sizeof(url));

	Format(sql, sizeof(sql), "UPDATE youtube_user SET action = '2', playlist_index = '%i', isplayed = '%s', url = '%s' WHERE steamid = '%s'", index, name, url, steamid[client]);
	SQL_TQuery(db, NextUpdateCallback, sql, client);
}

public void NextUpdateCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	if (hndl == null) {
		LogError("Query failed(NextUpdateCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	PlayerMenu(client);
}

public Action cmd_previous(int client, int args) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT playlist_id, playlist_index FROM youtube_user WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, BackCallback, sql, client);
}

public void BackCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	char sql[555];
	
	if (hndl == null) {
		LogError("Query failed(BackCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;

	int pid = SQL_FetchInt(hndl, 0);
	int index = SQL_FetchInt(hndl, 1);
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(index);
	pack.WriteCell(pid);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT MAX(`index`) FROM youtube_playlist_music WHERE id = '%i'", pid);
	SQL_TQuery(db, Back2Callback, sql, pack);
}

public void Back2Callback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	int index = pack.ReadCell();
	int pid = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(Back2Callback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	int max_index = SQL_FetchInt(hndl, 0);
	index = index - 1;
	if(index <= 0)
		index = max_index;
		
	pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(index);
	pack.WriteCell(pid);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT name, url FROM youtube_playlist_music WHERE id = '%i' AND `index` = '%i'", pid, index);
	SQL_TQuery(db, GetSoundInfoBackCallback, sql, pack);
}

public void GetSoundInfoBackCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char name[364];
	char url[364];
	char sql[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	int index = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(GetSoundInfoBackCallbackCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	SQL_FetchString(hndl, 0, name, sizeof(name));
	SQL_FetchString(hndl, 1, url, sizeof(url));
	
	Format(sql, sizeof(sql), "UPDATE youtube_user SET action = '1', playlist_index = '%i', isplayed = '%s', url = '%s' WHERE steamid = '%s'", index, name, url, steamid[client]);
	SQL_TQuery(db, BackUpdateCallback, sql, client);
}

public void BackUpdateCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	if (hndl == null) {
		LogError("Query failed(BackUpdateCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	PlayerMenu(client);
}

public Action cmd_video(int client, int args) {
	char url[555];
	char curl[555];
	cvar_url.GetString(curl, sizeof(curl));
	Format(url, sizeof(url), "%sindex.php", curl);
	motd(client, url);
	CPrintToChat(client, "%t", "loading", LOGO);
}

public void DBConnect() {
	char error[255];
	db = SQL_Connect("music", false, error, sizeof(error));
	
	if (db == null) {
		LogError("Unable to connect to database (%s)", error);
		return;
	}
	
	SQL_LockDatabase(db);
	SQL_FastQuery(db, "SET NAMES  'utf8'");
	
	char sql[6][] = {
		"CREATE TABLE IF NOT EXISTS `youtube` (`id` INT(15) NOT NULL AUTO_INCREMENT, `name` VARCHAR(555) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL, `url` VARCHAR(124) NOT NULL, `steamid` VARCHAR(32) NOT NULL, PRIMARY KEY(`id`))", 
		"CREATE TABLE IF NOT EXISTS `youtube_official` (`id` INT(15) NOT NULL AUTO_INCREMENT, `name` VARCHAR(555) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL, `playlist_id` VARCHAR(124) NOT NULL, `steamid` VARCHAR(32) NOT NULL, PRIMARY KEY(`id`))", 
		"CREATE TABLE IF NOT EXISTS `youtube_official_music` (`id` INT(15) NOT NULL, `index` INT(15) NOT NULL, `name` VARCHAR(555) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL)", 
		"CREATE TABLE IF NOT EXISTS `youtube_playlist` (`id` INT(15) NOT NULL AUTO_INCREMENT, `name` VARCHAR(555) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL, `steamid` VARCHAR(32) NOT NULL, PRIMARY KEY(`id`))", 
		"CREATE TABLE IF NOT EXISTS `youtube_playlist_music` (`id` INT(15) NOT NULL, `index` INT(15) NOT NULL, `name` VARCHAR(555) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL, `url` VARCHAR(124) NOT NULL)", 
		"CREATE TABLE IF NOT EXISTS `youtube_user` (`id` INT(15) NOT NULL AUTO_INCREMENT, `steamid` VARCHAR(32) NOT NULL, `volume` INT(3) NOT NULL, `etat` INT(1) NOT NULL, `getlist` VARCHAR(124) CHARACTER SET utf8 COLLATE utf8_bin DEFAULT NULL, `isplayed` VARCHAR(555) CHARACTER SET utf8 COLLATE utf8_bin DEFAULT NULL, `url` VARCHAR(124) DEFAULT NULL, `playlist_id` INT(15) NOT NULL, `playlist_index` INT(15) NOT NULL, `action` INT(1) NOT NULL, PRIMARY KEY(`id`))", 
	};
	for (int i = 0; i < 4; i++) {
		if (!SQL_FastQuery(db, sql[i])) {
			SQL_GetError(db, error, sizeof(error));
			LogError("Query failed: %s", error);
			LogError("Query dump: %s", sql[i]);
			return;
		}
	}
	SQL_UnlockDatabase(db);
}

void update_video(int client, char[] name, char[] url) {
	char sql[364];
	
	Format(sql, sizeof(sql), "SELECT volume FROM youtube_user WHERE steamid = '%s'", steamid[client]);
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(name);
	pack.WriteString(url);
	
	SQL_TQuery(db, VideoCallback, sql, pack);
}

public void VideoCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char urll[342];
	char curl[364];
	char name[555];
	char url[555];
	char sql[555];
	
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = pack.ReadCell();
	pack.ReadString(name, sizeof(name));
	pack.ReadString(url, sizeof(url));
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(VideoCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	int volumee = SQL_FetchInt(hndl, 0);
	
	cvar_url.GetString(curl, sizeof(curl));
	Format(urll, sizeof(urll), "%svideo.php?v=%s&steamid=%s&volume=%i", curl, url, steamid[client], volumee);
	motd(client, urll);
	yt_motd[client] = true;
	
	CPrintToChat(client, "%t", "loading", LOGO);
	CPrintToChat(client, "%t", "music display", LOGO, name);
	
	if (FindCharInString(name, '\\') == -1)
		ReplaceString(name, sizeof(name), "'", "\\'");
	Format(sql, sizeof(sql), "UPDATE youtube_user SET etat = '1', isplayed = '%s', url = '%s' WHERE steamid = '%s'", name, url, steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	PlayerMenu(client);
}

public void motd(int client, char[] url) {
	Format(motd_url[client], sizeof(motd_url[]), "%s", url);
	QueryClientConVar(client, "cl_disablehtmlmotd", check_convar);
}

public void check_convar(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue) {

	if (!StrEqual(cvarValue, "0")) {
		char msg[1024];
		Handle panel = CreatePanel();
		Format(msg, sizeof(msg), "________________\n   - HELP -   \n¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯\nYou must active MOTDs HTML, press F8\n \n Put in console : cl_disablehtmlmotd 0\n \n0 - Close");
		DrawPanelText(panel, msg);
		SendPanelToClient(panel, client, Nothing, 60);
	} else {
		KeyValues kv = new KeyValues("data");
		kv.SetString("title", "===music===");
		kv.SetNum("type", MOTDPANEL_TYPE_URL);
		kv.SetNum("cmd", 5);
		kv.SetString("msg", motd_url[client]);
		ShowVGUIPanel(client, "info", kv, false);
		delete kv;
	}
}
public int Nothing(Handle menu, MenuAction action, int param1, int param2) {}