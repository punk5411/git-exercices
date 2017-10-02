void MainPlaylistMenu(int client) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT name FROM youtube_playlist WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, MainPlaylistMenuCallback, sql, client);
}

public void MainPlaylistMenuCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char yt_pname[555];
	char translations[555];
	int client = data;
	
	if (hndl == null) {
		LogError("Query failed(MainPlaylistMenuCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	Menu menu = new Menu(MenuMainPlaylistMusic, MenuAction_DrawItem);
	menu.SetTitle("%t", "menu title");
	
	Format(translations, sizeof(translations), "%t%t", "official playlist", "connexion required");
	menu.AddItem("official", translations);
	
	menu.AddItem("disabled", "========");
	
	while (SQL_FetchRow(hndl)) {
		SQL_FetchString(hndl, 0, yt_pname, sizeof(yt_pname));
		menu.AddItem(yt_pname, yt_pname);
	}
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuMainPlaylistMusic(Menu menu, MenuAction action, int param1, int param2) {
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
			
			if (StrEqual(choice, "official"))
				official_result_menu(param1);
			else
				menu_list(param1, choice, sizeof(choice));
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

public void official_result_menu(int client) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT name, playlist_id FROM youtube_official WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, OfficialResultMenuCallback, sql, client);
}

public void OfficialResultMenuCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	
	if (hndl == null) {
		LogError("Query failed(OfficialResultMenuCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (!SQL_FetchRow(hndl)) {
		if (!yt_login[client]) {
			char url[555];
			char curl[364];
			cvar_url.GetString(curl, sizeof(curl));
			Format(url, sizeof(url), "%smotd.php?steamid=%s", curl, steamid[client]);
			motd(client, url);
		}
		CreateTimer(0.1, CheckOfficial, client);
	} else {
		SQL_Rewind(hndl);
		yt_login[client] = false;
		
		Menu menu = new Menu(MenuOfficialPlaylist);
		menu.SetTitle("%t", "menu title");
		
		while (SQL_FetchRow(hndl)) {
			char yt_name[555];
			char yt_playlist[555];
			SQL_FetchString(hndl, 0, yt_name, sizeof(yt_name));
			SQL_FetchString(hndl, 1, yt_playlist, sizeof(yt_playlist));
			menu.AddItem(yt_playlist, yt_name);
		}
		menu.ExitButton = true;
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
}
public Action CheckOfficial(Handle timer, int client) {
	if (!IsClientInGame(client))
		return Plugin_Stop;
	
	official_result_menu(client);
	return Plugin_Continue;
}

public int MenuOfficialPlaylist(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select:
		{
			char sql[555];
			char choice[248];
			char explode_choice[10][555];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			ExplodeString(choice, "|", explode_choice, sizeof(explode_choice[]), sizeof(explode_choice[]));
			
			update_playlist(param1, explode_choice[0], explode_choice[1], explode_choice[2], explode_choice[3]);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				MainPlaylistMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void menu_list(int client, char[] choice, int l) {
	char sql[364];
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(choice);
	pack.Reset();
	
	ReplaceString(choice, l, "'", "\\'");
	Format(sql, sizeof(sql), "SELECT id FROM youtube_playlist WHERE name = '%s' AND steamid = '%s'", choice, steamid[client]);
	SQL_TQuery(db, MenuListCallback, sql, pack);
}

public void MenuListCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	char choice[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(choice, sizeof(choice));
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(MenuListCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	int pid = SQL_FetchInt(hndl, 0);
	
	pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(choice);
	pack.WriteCell(pid);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT `index`, name, url FROM youtube_playlist_music WHERE id = '%i' ORDER BY `index`", pid);
	SQL_TQuery(db, MenuListSelectCallback, sql, pack);
}

public void MenuListSelectCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int index;
	char pname[555];
	char purl[555];
	char yt_menuitem[555];
	char menu_item[555];
	char translations[555];
	char choice[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(choice, sizeof(choice));
	int pid = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(MenuListSelectCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	Menu menu = new Menu(MenuListMusic, MenuAction_DrawItem);
	menu.SetTitle("%t", "menu title");
	
	int count = 0;
	while (SQL_FetchRow(hndl)) {
		count++;
		index = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, pname, sizeof(pname));
		SQL_FetchString(hndl, 2, purl, sizeof(purl));
		
		if (count == 1) {
			Format(translations, sizeof(translations), "%t", "menu item play");
			Format(menu_item, sizeof(menu_item), "%s|%s|%i|%i|play", pname, purl, index, pid);
			menu.AddItem(menu_item, translations);
			
			Format(translations, sizeof(translations), "%t", "menu item delete");
			Format(menu_item, sizeof(menu_item), "%i|delete", pid);
			menu.AddItem(menu_item, translations);
			
			menu.AddItem("disabled", "========");
		}
		Format(yt_menuitem, sizeof(yt_menuitem), "%s|%s|%i|%i", pname, purl, index, pid);
		menu.AddItem(yt_menuitem, pname);
	}
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuListMusic(Menu menu, MenuAction action, int param1, int param2) {
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
			char sql[555];
			char choice[248];
			char explode_choice[10][999];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			ExplodeString(choice, "|", explode_choice, sizeof(explode_choice[]), sizeof(explode_choice[]));
			if (StrEqual(explode_choice[4], "play")) {
				update_playlist(param1, explode_choice[0], explode_choice[1], explode_choice[2], explode_choice[3]);
				PlayerMenu(param1);
			} else if (StrEqual(explode_choice[1], "delete")) {
				Format(sql, sizeof(sql), "DELETE FROM youtube_playlist WHERE id = '%s' AND steamid = '%s'", explode_choice[0], steamid[param1]);
				SQL_TQuery(db, SQLCallback, sql, param1);
				Format(sql, sizeof(sql), "DELETE FROM youtube_playlist_music WHERE id = '%s'", explode_choice[0]);
				SQL_TQuery(db, SQLCallback, sql, param1);
				MainMenu(param1);
			} else {
				exec_menu_playlist(param1, choice);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				MainPlaylistMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void exec_menu_playlist(int client, char[] choice) {
	char yt_menu_play[124];
	char translations[124];
	char yt_menu_playlist[124];
	
	Menu menu = new Menu(MenuExecMusicPlaylist);
	menu.SetTitle("%t", "menu title");
	
	Format(yt_menu_play, sizeof(yt_menu_play), "%s|play", choice);
	Format(translations, sizeof(translations), "%t", "menu item play");
	menu.AddItem(yt_menu_play, translations);
	
	Format(yt_menu_playlist, sizeof(yt_menu_playlist), "%s|delete", choice);
	Format(translations, sizeof(translations), "%t", "menu item del music");
	menu.AddItem(yt_menu_playlist, translations);
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuExecMusicPlaylist(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select:
		{
			char sql[555];
			char choice[555];
			char explode_choice[10][999];
			GetMenuItem(menu, param2, choice, sizeof(choice));
			ExplodeString(choice, "|", explode_choice, sizeof(explode_choice[]), sizeof(explode_choice[]));
			if (StrEqual(explode_choice[4], "play")) {
				update_playlist(param1, explode_choice[0], explode_choice[1], explode_choice[2], explode_choice[3]);
				PlayerMenu(param1);
			} else if (StrEqual(explode_choice[4], "delete")) {
				Format(sql, sizeof(sql), "DELETE FROM youtube_playlist_music WHERE id = '%s' AND `index` = '%s'", explode_choice[3], explode_choice[2]);
				SQL_TQuery(db, SQLCallback, sql, param1);
				update_playlist_index(param1, StringToInt(explode_choice[3]), StringToInt(explode_choice[2]));
				
				DataPack pack = new DataPack();
				pack.WriteCell(param1);
				pack.WriteCell(StringToInt(explode_choice[3]));
				pack.Reset();
				
				MainPlaylistMenu(param1);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				MainPlaylistMenu(param1);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void add_playlist_menu(int client, char[] name, char[] url) {
	char sql[364];
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(name);
	pack.WriteString(url);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT id, name FROM youtube_playlist WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, MenuAddPlaylistCallback, sql, pack);
}

public void MenuAddPlaylistCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char name[555];
	char url[555];
	char pname[555];
	char yt_pchoice[555];
	char yt_pchoicee[124];
	char translations[124];
	int pid;
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(name, sizeof(name));
	pack.ReadString(url, sizeof(url));
	pack.Reset();
	
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(MenuAddPlaylistCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	Menu menu = new Menu(MenuAddPlaylistMusic);
	menu.SetTitle("%t", "menu title");
	
	if (player_menu[client])
		Format(yt_pchoicee, sizeof(yt_pchoicee), "%s|%s|create|1", name, url);
	else
		Format(yt_pchoicee, sizeof(yt_pchoicee), "%s|%s|create", name, url);
	player_menu[client] = false;
	
	Format(translations, sizeof(translations), "%t", "menu item create playlist");
	menu.AddItem(yt_pchoicee, translations);
	
	while (SQL_FetchRow(hndl)) {
		pid = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, pname, sizeof(pname));
		
		Format(yt_pchoice, sizeof(yt_pchoice), "%s|%s|%i", name, url, pid);
		menu.AddItem(yt_pchoice, pname);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuAddPlaylistMusic(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select:
		{
			char choice[999];
			char choicee[999];
			char explode_choice[10][999];
			char sql[364];
			
			GetMenuItem(menu, param2, choice, sizeof(choice));
			ExplodeString(choice, "|", explode_choice, sizeof(explode_choice[]), sizeof(explode_choice[]));
			
			if (StrEqual(explode_choice[3], "1"))
				player_menu[param1] = true;
			
			if (StrEqual(explode_choice[2], "create")) {
				create_playlist[param1] = true;
				CPrintToChat(param1, "%t", "create playlist", LOGO);
				Format(selected_song[param1], sizeof(selected_song), "%s|%s", explode_choice[0], explode_choice[1]);
			} else {
				DataPack pack = new DataPack();
				pack.WriteCell(param1);
				pack.WriteCell(StringToInt(explode_choice[2]));
				pack.WriteString(explode_choice[0]);
				pack.WriteString(explode_choice[1]);
				pack.Reset();
				
				if (FindCharInString(explode_choice[0], '\\') == -1)
					ReplaceString(explode_choice[0], sizeof(explode_choice[]), "'", "\\'");
				Format(sql, sizeof(sql), "SELECT id FROM youtube_playlist_music WHERE id = ' % s' AND name = ' % s' AND url = ' % s'", explode_choice[2], explode_choice[0], explode_choice[1]);
				SQL_TQuery(db, MenuAddPlaylistCheckCallback, sql, pack);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) {
				if(!player_menu[param1])
					exec_menu(param1, selected_song[param1]);
				else
					PlayerMenu(param1);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public void MenuAddPlaylistCheckCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	char name[555];
	char url[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	int pid = pack.ReadCell();
	pack.ReadString(name, sizeof(name));
	pack.ReadString(url, sizeof(url));
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(MenuAddPlaylistCheckCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (SQL_FetchRow(hndl)) {
		CPrintToChat(client, "%t", "music already added", LOGO);
		add_playlist_menu(client, name, url);
		return;
	}
	
	pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(name);
	pack.WriteString(url);
	pack.WriteCell(pid);
	pack.Reset();
				
	Format(sql, sizeof(sql), "SELECT `index` FROM youtube_playlist_music WHERE id = ' % i' ORDER BY `index` DESC LIMIT 1", pid);
	SQL_TQuery(db, MenuAddPlaylistMusicCallback, sql, pack);
}

public void MenuAddPlaylistMusicCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int maxindex = 0;
	char explode_choice[555];
	char explode_choice1[555];
	char sql[555];
	char choicee[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(explode_choice, sizeof(explode_choice));
	pack.ReadString(explode_choice1, sizeof(explode_choice1));
	int explode_choice2 = pack.ReadCell();
	delete pack;
	
	if (hndl == null) {
		LogError("Query failed(MenuAddPlayListMusicCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (SQL_FetchRow(hndl)) {
		maxindex = SQL_FetchInt(hndl, 0);
		maxindex = maxindex + 1;
	}
	
	if (FindCharInString(explode_choice, '\\') == -1)
		ReplaceString(explode_choice, sizeof(explode_choice), "'", "\\'");
	Format(sql, sizeof(sql), "INSERT INTO youtube_playlist_music (id, `index`, name, url) VALUES (' % i', ' % i', ' % s', ' % s')", explode_choice2, maxindex, explode_choice, explode_choice1);
	SQL_TQuery(db, SQLCallback, sql, client);
	
	Format(choicee, sizeof(choicee), "%s|%s", explode_choice, explode_choice1);
	create_playlist[client] = false;

	if(!player_menu[client])
		exec_menu(client, choicee);
	else
		PlayerMenu(client);
	player_menu[client] = false;
}

void update_playlist(int client, char[] name, char[] url, char[] index, char[] id) {
	int ind = StringToInt(index);
	int idd = StringToInt(id);
	char sql[364];
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(ind);
	pack.WriteCell(idd);
	pack.WriteString(name);
	pack.WriteString(url);
	pack.Reset();
	
	Format(sql, sizeof(sql), "SELECT volume FROM youtube_user WHERE steamid = ' % s'", steamid[client]);
	SQL_TQuery(db, UpdatePlaylistCallback, sql, pack);
}

public void UpdatePlaylistCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	char name[555];
	char url[555];
	char urll[555];
	char curl[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	int ind = pack.ReadCell();
	int idd = pack.ReadCell();
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
	Format(urll, sizeof(urll), "%splaylist.php?id=%i&index=%i&steamid=%s&volume=%i", curl, idd, ind, steamid[client], volumee);
	motd(client, urll);
	yt_motd[client] = true;
	
	CPrintToChat(client, "%t", "loading", LOGO);
	CPrintToChat(client, "%t", "music display", LOGO, name);
	
	if (FindCharInString(name, '\\') == -1)
		ReplaceString(name, sizeof(name), "'", "\\'");
	Format(sql, sizeof(sql), "UPDATE youtube_user SET etat = '1', isplayed = ' % s', playlist_id = ' % i', url = ' % s' WHERE steamid = ' % s'", name, idd, url, steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	
	PlayerMenu(client);
}

Action playlist_created(int client, char[] arg, int args) {
	char sql[555];
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(arg);
	pack.Reset();
	
	if (FindCharInString(arg, '\\') == -1)
		ReplaceString(arg, args, "'", "\\'");
	Format(sql, sizeof(sql), "SELECT name FROM youtube_playlist WHERE name = ' % s' AND steamid = ' % s'", arg, steamid[client]);
	SQL_TQuery(db, PlaylistCreatedCallback, sql, pack);
	create_playlist[client] = false;
	return Plugin_Handled;
}

public void PlaylistCreatedCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	char arg[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(arg, sizeof(arg));
	pack.Reset();
	
	if (hndl == null) {
		LogError("Query failed(PlaylistCreatedCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (SQL_FetchRow(hndl)) {
		CPrintToChat(client, "%t", "playlist name error", LOGO, arg);
		create_playlist[client] = true;
		return;
	}
	
	if (FindCharInString(arg, '\\') == -1)
		ReplaceString(arg, sizeof(arg), "'", "\\'");
	Format(sql, sizeof(sql), "INSERT INTO youtube_playlist (name, steamid) VALUES (' % s', ' % s')", arg, steamid[client]);
	SQL_TQuery(db, PlaylistCreatedMusicCallback, sql, pack);
}

public void PlaylistCreatedMusicCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	char arg[555];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(arg, sizeof(arg));
	pack.Reset();
	
	if (hndl == null) {
		LogError("Query failed(PlaylistCreatedMusicCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (FindCharInString(arg, '\\') == -1)
		ReplaceString(arg, sizeof(arg), "'", "\\'");
	Format(sql, sizeof(sql), "SELECT id FROM youtube_playlist WHERE name = ' % s' AND steamid = ' % s'", arg, steamid[client]);
	SQL_TQuery(db, PlaylistCreatedSelectCallback, sql, pack);
}

public void PlaylistCreatedSelectCallback(Handle owner, Handle hndl, const char[] error, any data) {
	char sql[555];
	char arg[555];
	char explode_choice[10][999];
	
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();
	pack.ReadString(arg, sizeof(arg));
	delete pack;
	
	ExplodeString(selected_song[client], "|", explode_choice, sizeof(explode_choice[]), sizeof(explode_choice[]));
	
	if (hndl == null) {
		LogError("Query failed(PlaylistCreatedSelectCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	int pid = SQL_FetchInt(hndl, 0);
	
	if (FindCharInString(explode_choice[0], '\\') == -1)
		ReplaceString(explode_choice[0], sizeof(explode_choice[]), "'", "\\'");
	Format(sql, sizeof(sql), "INSERT INTO youtube_playlist_music (id, `index`, name, url) VALUES (' % i', '0', ' % s', ' % s')", pid, explode_choice[0], explode_choice[1]);
	SQL_TQuery(db, SQLCallback, sql, client);
	
	CPrintToChat(client, " % t", "playlist created", LOGO, arg);
	
	if(player_menu[client])
		PlayerMenu(client);
	else
		exec_menu(client, selected_song[client]);
	player_menu[client] = false;
} 