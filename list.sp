Action search_list(int client, char[] arg, int l) {
	char sql[364];
	char curl[364];
	cvar_url.GetString(curl, sizeof(curl));
	
	Format(sql, sizeof(sql), "DELETE FROM youtube WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	
	if(!yt_motd[client]) {
		char url[555];
		Format(url, sizeof(url), "%svideo.php?steamid=%s", curl, steamid[client]);
		motd(client, url);
	}

	if (FindCharInString(arg, '\\') == -1)	
		ReplaceString(arg, l, "'", "\\'");
	Format(sql, sizeof(sql), "UPDATE youtube_user SET getlist = '%s' WHERE steamid = '%s'", arg, steamid[client]);
	SQL_TQuery(db, SQLCallback, sql, client);
	
	Format(search_arg[client], sizeof(search_arg), "%s", arg);
	CreateTimer(0.1, CheckList, client);
	CPrintToChat(client, "%t", "loading", LOGO);
	do_search[client] = false;
	
	return Plugin_Handled;
}

public Action CheckList(Handle Timer, int client) {
	if (!IsClientInGame(client))
		return Plugin_Stop;
	
	char sql[364];
	Format(sql, sizeof(sql), "SELECT name, url FROM youtube WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, CheckListCallback, sql, client);
	return Plugin_Continue;
}

public void CheckListCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	
	if (hndl == null) {
		LogError("Query failed(SearchListCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (SQL_FetchRow(hndl)) {
		search_result_menu(client);
		char sql[364];
		Format(sql, sizeof(sql), "UPDATE youtube_user SET getlist = NULL WHERE steamid = '%s'", steamid[client]);
		SQL_TQuery(db, SQLCallback, sql, client);
	} 
	else
		CreateTimer(0.1, CheckList, client);
}

void search_result_menu(int client) {
	char sql[364];
	Format(sql, sizeof(sql), "SELECT name, url FROM youtube WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, SearchResultMenuCallback, sql, client);
}

public void SearchResultMenuCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	char translations[555];
	
	if (hndl == null) {
		LogError("Query failed(SearchResultMenuCallback): %s", error);
		return;
	}
	if (client == 0 || !SQL_FetchRow(hndl))
		return;
	
	Menu menu = new Menu(MenuMusic, MenuAction_DrawItem);
	menu.SetTitle("%t", "menu title");
	
	Format(translations, sizeof(translations), "%t", "menu search arg", search_arg[client]);
	menu.AddItem("disabled", translations);
	
	Format(translations, sizeof(translations), "%t", "menu item search new");
	menu.AddItem("new", translations);
	
	menu.AddItem("disabled", "========");
	
	while (SQL_FetchRow(hndl)) {
		char yt_name[555];
		char yt_url[555];
		char yt_menu[555];
		
		SQL_FetchString(hndl, 0, yt_name, sizeof(yt_name));
		SQL_FetchString(hndl, 1, yt_url, sizeof(yt_url));
		Format(yt_menu, sizeof(yt_menu), "%s|%s", yt_name, yt_url);
		
		menu.AddItem(yt_menu, yt_name);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
} 