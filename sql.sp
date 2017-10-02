public void client_connect(int client) {
	char sql[555];
	Format(sql, sizeof(sql), "SELECT * FROM youtube_user WHERE steamid = '%s'", steamid[client]);
	SQL_TQuery(db, ConnectCallback, sql, client);
}

public void ConnectCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	if (hndl == null) {
		LogError("Query failed(ConnectCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
	
	if (SQL_GetRowCount(hndl) <= 0) {
		char sql[555];
		Format(sql, sizeof(sql), "INSERT INTO youtube_user (steamid, volume, etat, getlist, isplayed, playlist_id, url, channel_id, action) VALUES ('%s', '50', '0', NULL, NULL, '-1', NULL, NULL, '0')", steamid[client]);
		SQL_TQuery(db, SQLCallback, sql, client);
	}
}

public void SQLCallback(Handle owner, Handle hndl, const char[] error, any data) {
	int client = data;
	if (hndl == null) {
		LogError("Query failed(SQLCallback): %s", error);
		return;
	}
	if (client == 0)
		return;
}

public void update_playlist_index(int client, int id, int index) {
	char sql[555];
	Format(sql, sizeof(sql), "UPDATE youtube_playlist_music SET `index` = `index` - 1 WHERE id = '%i' AND `index` > '%i'", id, index);
	SQL_TQuery(db, SQLCallback, sql, client);
}