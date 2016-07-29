class PlayerState
{
	EHandle plr;
	EHandle targetPlr; // if set, hud will only display for this player
	CScheduledFunction@ interval; // handle to the interval
}

// persistent-ish player data, organized by steam-id or username if on a LAN server, values are @PlayerState
dictionary player_states;
bool abort_updates = false;

string font_folder = "sprites/as_lost/consolas/";
array<string> font_chars;
int MAX_FONT_CHARS = 96;
float updateFreq = 0.07f; // delay between name tag updates
int maxNameLength = 16;

dictionary g_charmap;
void loadCharMap()
{
	g_charmap[' '] = 0;
	g_charmap['!'] = 1;
	g_charmap['"'] = 2;
	g_charmap['#'] = 3;
	g_charmap['$'] = 4;
	g_charmap['%'] = 5;
	g_charmap['&'] = 6;
	g_charmap["'"] = 7;
	g_charmap['('] = 8;
	g_charmap[')'] = 9;
	g_charmap['*'] = 10;
	g_charmap['+'] = 11;
	g_charmap[','] = 12;
	g_charmap['-'] = 13;
	g_charmap['.'] = 14;
	g_charmap['/'] = 15;
	g_charmap['0'] = 16;
	g_charmap['1'] = 17;
	g_charmap['2'] = 18;
	g_charmap['3'] = 19;
	g_charmap['4'] = 20;
	g_charmap['5'] = 21;
	g_charmap['6'] = 22;
	g_charmap['7'] = 23;
	g_charmap['8'] = 24;
	g_charmap['9'] = 25;
	g_charmap[':'] = 26;
	g_charmap[';'] = 27;
	g_charmap['<'] = 28;
	g_charmap['='] = 29;
	g_charmap['>'] = 30;
	g_charmap['?'] = 31;
	g_charmap['@'] = 32;
	g_charmap['A'] = 33;
	g_charmap['B'] = 34;
	g_charmap['C'] = 35;
	g_charmap['D'] = 36;
	g_charmap['E'] = 37;
	g_charmap['F'] = 38;
	g_charmap['G'] = 39;
	g_charmap['H'] = 40;
	g_charmap['I'] = 41;
	g_charmap['J'] = 42;
	g_charmap['K'] = 43;
	g_charmap['L'] = 44;
	g_charmap['M'] = 45;
	g_charmap['N'] = 46;
	g_charmap['O'] = 47;
	g_charmap['P'] = 48;
	g_charmap['Q'] = 49;
	g_charmap['R'] = 50;
	g_charmap['S'] = 51;
	g_charmap['T'] = 52;
	g_charmap['U'] = 53;
	g_charmap['V'] = 54;
	g_charmap['W'] = 55;
	g_charmap['X'] = 56;
	g_charmap['Y'] = 57;
	g_charmap['Z'] = 58;
	g_charmap['['] = 59;
	g_charmap['\\'] = 60;
	g_charmap[']'] = 61;
	g_charmap['^'] = 62;
	g_charmap['_'] = 63;
	g_charmap['`'] = 64;
	g_charmap['a'] = 65;
	g_charmap['b'] = 66;
	g_charmap['c'] = 67;
	g_charmap['d'] = 68;
	g_charmap['e'] = 69;
	g_charmap['f'] = 70;
	g_charmap['g'] = 71;
	g_charmap['h'] = 72;
	g_charmap['i'] = 73;
	g_charmap['j'] = 74;
	g_charmap['k'] = 75;
	g_charmap['l'] = 76;
	g_charmap['m'] = 77;
	g_charmap['n'] = 78;
	g_charmap['o'] = 79;
	g_charmap['p'] = 80;
	g_charmap['q'] = 81;
	g_charmap['r'] = 82;
	g_charmap['s'] = 83;
	g_charmap['t'] = 84;
	g_charmap['u'] = 85;
	g_charmap['v'] = 86;
	g_charmap['w'] = 87;
	g_charmap['x'] = 88;
	g_charmap['y'] = 89;
	g_charmap['z'] = 90;
	g_charmap['{'] = 91;
	g_charmap['|'] = 92;
	g_charmap['}'] = 93;
	g_charmap['~'] = 94;
	// 95th character is the "error" code and just shows a box
}

// Will create a new state if the requested one does not exit
PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	if (plr is null or !plr.IsConnected())
		return null;
		
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
	if ( !player_states.exists(steamId) )
	{
		PlayerState state;
		state.plr = plr;
		player_states[steamId] = state;
		//println("ADDED STATE FOR: " + steamId);
	}
	return cast<PlayerState@>( player_states[steamId] );
}

void init()
{
	for (int i = 0; i < MAX_FONT_CHARS; i++)
	{
		string char_spr = font_folder + i + ".spr";
		g_Game.PrecacheModel(char_spr);
		font_chars.insertLast(char_spr);
	}
	
	loadCharMap();
	populatePlayerStates();
	//g_Scheduler.SetTimeout("loadMapWaypoints", 0.5);
	//g_Scheduler.SetInterval("renderAllWaypoints", 0.1);
}

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "w00tguy123 - forums.svencoop.com" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Player::ClientDisconnect, @ClientLeave );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );
	
	g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );
	
	player_states.deleteAll();
	
	init();
}

void MapInit()
{
	abort_updates = false;
	init();
}

HookReturnCode MapChange()
{
	abort_updates = true;
	
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );

		if (state.interval !is null)
			g_Scheduler.RemoveTimer(state.interval);
	}
	
	player_states.deleteAll();
	return HOOK_CONTINUE;
}

void populatePlayerStates()
{	
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player"); 
		if (ent !is null)
		{
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			getPlayerState(plr);
			//println("TRY STATE FOR: " + plr.pev.netname);
		}
	} while (ent !is null);
}

HookReturnCode ClientJoin( CBasePlayer@ plr )
{
	getPlayerState(plr);
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ leaver)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( leaver.edict() );
	if (steamId == 'STEAM_ID_LAN') {
		steamId = leaver.pev.netname;
	}
		
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBaseEntity@ plr = state.plr;
		if (stateKeys[i] == steamId)
		{
			if (state.interval !is null)
				g_Scheduler.RemoveTimer(state.interval);
			state.plr = null;
			break;
		}
	}
	player_states.delete(steamId);
	
	return HOOK_CONTINUE;
}

void displayText(Vector pos, CBasePlayer@ observer, CBaseEntity@ plr, string text, float scale)
{
	array<string> lines = text.Split("\n");
	
	// adjust scale so that it is readable at a distance
	float dist = (pos - (observer.pev.origin + observer.pev.view_ofs)).Length();
	scale = Math.min(25.0f, (dist / 1024.0f) + scale);
	
	Math.MakeVectors( observer.pev.v_angle );
	Vector lookDir = g_Engine.v_forward;
	
	// flattened look direction
	Vector flatLookDir = lookDir;
	flatLookDir.z = 0;
	flatLookDir = flatLookDir.Normalize();
	
	// text axis
	Vector textAxis = CrossProduct(flatLookDir, Vector(0,0,1));
	//te_beampoints(observer.pev.origin, observer.pev.origin + textAxis*128);
	
	Vector newlineAxis = CrossProduct(lookDir, textAxis).Normalize();
	//te_beampoints(observer.pev.origin, observer.pev.origin + newlineAxis*128);
	
	float charWidth = 12.0f*scale;	
	float charHeight = 24.0f*scale;
	pos.z += charHeight*lines.length()*0.5f;
	
	// calculate a bounding square for the text
	float height = lines.length()*charHeight;
	float width = 0;
	for (uint k = 0; k < lines.length(); k++)
		if (int(lines[k].Length()) > width)
			width = lines[k].Length();
	width *= charWidth;
	
	Vector textOri = pos + newlineAxis*(height*0.5f - charHeight*0.5f);
	Vector textVert = newlineAxis*height*0.5f;
	Vector textHori = textAxis*width*0.5f;
	
	
	TraceResult tr, tr2;
	CBaseEntity@ pHit, pHit2;
	edict_t@ no_collide = plr !is null ? plr.edict() : null;
	
	//te_beampoints(textOri - textVert, textOri + textVert);
	
	
	// make sure text isn't vertically colliding with anything
	g_Utility.TraceHull( textOri - textVert, textOri + textVert, ignore_monsters, point_hull, no_collide, tr );
	g_Utility.TraceHull( textOri + textVert, textOri - textVert, ignore_monsters, point_hull, no_collide, tr2 );
	if (tr.flFraction < 1.0f or tr2.flFraction < 1.0f)
	{
		float topDist = tr.flFraction;
		float bottomDist = tr2.flFraction;
		
		// move the least amount necessary, and in the direction that the player will see it best
		bool belowPlayer = textOri.z < observer.pev.origin.z + observer.pev.view_ofs.z;
		//println("BELOW? " + belowPlayer);
		if ((topDist > bottomDist or bottomDist == 1) and topDist < 1 and (belowPlayer or bottomDist == 1))
			pos = pos - newlineAxis*height*(1.0f-topDist);
		else
			pos = pos + newlineAxis*height*(1.0f-bottomDist);
		textOri = pos + newlineAxis*(height*0.5f - charHeight*0.5f);
	}
	
	// make sure text isn't horizontally colliding with anything
	g_Utility.TraceHull( textOri - textHori, textOri + textHori, ignore_monsters, point_hull, no_collide, tr );
	g_Utility.TraceHull( textOri + textHori, textOri - textHori, ignore_monsters, point_hull, no_collide, tr2 );
	if (tr.flFraction < 1.0f or tr2.flFraction < 1.0f)
	{
		float topDist = tr.flFraction;
		float bottomDist = tr2.flFraction;
		
		// move the least amount necessary
		if ((topDist > bottomDist or bottomDist == 1) and topDist < 1)
			pos = pos - textAxis*width*(1.0f-topDist);
		else
			pos = pos + textAxis*width*(1.0f-bottomDist);
		textOri = pos + newlineAxis*(height*0.5f - charHeight*0.5f);
	}
	
	//te_beampoints(observer.pev.origin, textOri + textVert);
	
	float y = 0;
	for (uint k = 0; k < lines.length(); k++)
	{
		float x = -float(lines[k].Length() * charWidth) / 2.0f;
		x += charWidth * 0.5f;

		for (uint i = 0; i < lines[k].Length(); i++)
		{
			int c = MAX_FONT_CHARS-1;
			string ch = string(lines[k][i]);
			if (g_charmap.exists(ch))
				c = int(g_charmap[ch]);
			//te_explosion(pos + textAxis*x, font_chars[c], int(scale*10), 9, 14);
			te_sprite(pos + textAxis*x + newlineAxis*y, font_chars[c], int(scale*10), 180, MSG_ONE_UNRELIABLE, observer.edict());
			x += charWidth;
		}

		y += charHeight;
	}
}

// display name overhead
void showNameTag(CBasePlayer@ observer, CBaseEntity@ target, bool tags_only)
{
	if (observer is null or target is null or abort_updates)
		return;
		
	string name = target.pev.netname;
	
	if (int(name.Length()) > maxNameLength)
	{
		int middle = name.Length() / 2;
		name = name.SubString(0, 7) + ".." + name.SubString(name.Length()-7, name.Length());
	}
	
	Vector delta = target.pev.origin - observer.pev.origin;
	float dist = delta.Length();
	
	TraceResult tr, tr2;
	Vector observerHead = observer.pev.origin + observer.pev.view_ofs ;
	Vector targetHead = target.pev.origin + target.pev.view_ofs + Vector(0,0,40);
	g_Utility.TraceHull( observerHead, targetHead, ignore_monsters, point_hull, observer.edict(), tr );
	g_Utility.TraceHull( observerHead, targetHead - Vector(0,0,32), ignore_monsters, point_hull, observer.edict(), tr2 );
	float maxDist = Math.min(2048.0f, tr.flFraction*dist);
	
	CBaseEntity@ pHit = g_EntityFuncs.Instance( tr.pHit );
	CBaseEntity@ pHit2 = g_EntityFuncs.Instance( tr2.pHit );
	bool lineOfSight = pHit !is null and pHit.entindex() == target.entindex() or tr.flFraction == 1;
	bool bodySight = pHit2 !is null and pHit2.entindex() == target.entindex() or tr2.flFraction == 1;
	bool isSelf = observer.entindex() == target.entindex();
	lineOfSight = lineOfSight or isSelf;
	
	if (isSelf)
		return;
	
	float meters = Math.max(0, (dist/33.0f) - 1.0f);
	string dstr = "" + int(meters) + "m\n";
	
	//target.pev.netname = "TheQuick Brown Fox Jumped Over" + target.entindex();
	//target.pev.netname = "w00tguy123";
	
	Vector pos;
	if (lineOfSight)
	{
		pos = target.pev.origin;
		pos.z += 50.0f;
		dstr = "";
		displayText(pos, observer, target, dstr + name, 0.2f);
	}
	else
	{
		//if (1==1) return;
		pos = observer.pev.origin + delta.Normalize()*maxDist*0.99f;
		
		if (bodySight)
		{
			dstr = "";
			pos.z += 15.0f;
		}
		else
			pos.z += 20.0f;
		if (!tags_only)
			displayText(pos, observer, target, dstr + name, 0.2f);
	}
}

void helpLostPlayer(CBasePlayer@ plr, CBasePlayer@ target, bool tags_only)
{	
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBaseEntity@ p = state.plr;
		if (target !is null and target.entindex() != p.entindex())
			continue;
		showNameTag(plr, p, tags_only);
	}
}

string getPlayerUniqueId(CBasePlayer@ plr)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'STEAM_ID_BOT') {
		steamId = plr.pev.netname;
	}
	return steamId;
}

// get player by name, partial name, or steamId
CBasePlayer@ getPlayer(CBasePlayer@ caller, string name)
{
	name = name.ToLowercase();
	int partialMatches = 0;
	CBasePlayer@ partialMatch;
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player");
		if (ent !is null) {
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			string plrName = string(plr.pev.netname).ToLowercase();
			string plrId = getPlayerUniqueId(plr).ToLowercase();
			if (plrName == name)
				return plr;
			else if (plrId == name)
				return plr;
			else if (plrName.Find(name) != uint(-1))
			{
				@partialMatch = plr;
				partialMatches++;
			}
		}
	} while (ent !is null);
	
	if (partialMatches == 1) {
		return partialMatch;
	} else if (partialMatches > 1) {
		g_PlayerFuncs.SayText(caller, 'There are ' + partialMatches + ' players that have "' + name + '" in their name. Be more specific.');
	} else {
		g_PlayerFuncs.SayText(caller, 'There is no player named "' + name + '"');
	}
	
	return null;
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args)
{
	PlayerState@ state = getPlayerState(plr);
	
	if ( args.ArgC() >= 1 )
	{
		if ( args[0] == ".lost" )
		{
			int numPlayers = player_states.getSize()-1;
			
			CBasePlayer@ targetPlr = null;
			bool tagsOnly = false;
			if ( args.ArgC() >= 2 )
			{
				if (args[1][0] == '\\')
					tagsOnly = true;
				else
				{
					@targetPlr = getPlayer(plr, args[1]);
					if (targetPlr is null)
						return true;
					if (targetPlr.entindex() == plr.entindex())
					{
						g_PlayerFuncs.SayText(plr, "Can't track yourself!");
						return true;
					}
				}
			}
			
			float duration = 5.0f; // default 10 seconds
			int numIntervals = int((duration / updateFreq));
			numIntervals = -1;
			
			if (state.interval !is null)
			{
				g_Scheduler.RemoveTimer(state.interval);
				@state.interval = null;
				if (targetPlr is null and !tagsOnly)
				{
					g_PlayerFuncs.SayText(plr, "Tracking disabled");
					return true;
				}
			}
			@state.interval = g_Scheduler.SetInterval("helpLostPlayer", updateFreq, numIntervals, @plr, @targetPlr, tagsOnly);
			
			if (tagsOnly)
			{
				g_PlayerFuncs.SayText(plr, "Name tags enabled");
			}
			else
			{
				string plrTxt = numPlayers == 1 ? "player" : "players";
				if (targetPlr !is null)
					g_PlayerFuncs.SayText(plr, "Tracking " + targetPlr.pev.netname);
				else
				{
					if (numPlayers > 0)
						g_PlayerFuncs.SayText(plr, "Tracking " + numPlayers + " " + plrTxt);
					else
						g_PlayerFuncs.SayText(plr, "Tracking enabled (no other players have joined yet)");
				}
			}
			
			return true;
		}
	}
	
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams )
{	
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, args))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	
	return HOOK_CONTINUE;
}

CClientCommand _lost("lost", "Find other players", @consoleCmd );

void consoleCmd( const CCommand@ args )
{
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args);
}

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void te_explosion(Vector pos, string sprite="sprites/zerogxplode.spr", int scale=10, int frameRate=15, int flags=0, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_EXPLOSION);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(scale);m.WriteByte(frameRate);m.WriteByte(flags);m.End(); }
void te_sprite(Vector pos, string sprite="sprites/zerogxplode.spr", uint8 scale=10, uint8 alpha=200, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_SPRITE);m.WriteCoord(pos.x); m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(scale); m.WriteByte(alpha);m.End();}
void te_beampoints(Vector start, Vector end, string sprite="sprites/laserbeam.spr", uint8 frameStart=0, uint8 frameRate=100, uint8 life=1, uint8 width=2, uint8 noise=0, Color c=GREEN, uint8 scroll=32, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BEAMPOINTS);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(end.x);m.WriteCoord(end.y);m.WriteCoord(end.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(frameStart);m.WriteByte(frameRate);m.WriteByte(life);m.WriteByte(width);m.WriteByte(noise);m.WriteByte(c.r);m.WriteByte(c.g);m.WriteByte(c.b);m.WriteByte(c.a);m.WriteByte(scroll);m.End(); }

class Color
{ 
	uint8 r, g, b, a;
	Color() { r = g = b = a = 0; }
	Color(uint8 r, uint8 g, uint8 b) { this.r = r; this.g = g; this.b = b; this.a = 255; }
	Color(uint8 r, uint8 g, uint8 b, uint8 a) { this.r = r; this.g = g; this.b = b; this.a = a; }
	Color(float r, float g, float b, float a) { this.r = uint8(r); this.g = uint8(g); this.b = uint8(b); this.a = uint8(a); }
	Color (Vector v) { this.r = uint8(v.x); this.g = uint8(v.y); this.b = uint8(v.z); this.a = 255; }
	string ToString() { return "" + r + " " + g + " " + b + " " + a; }
	Vector getRGB() { return Vector(r, g, b); }
}

Color RED    = Color(255,0,0);
Color GREEN  = Color(0,255,0);
Color BLUE   = Color(0,0,255);
Color YELLOW = Color(255,255,0);
Color ORANGE = Color(255,127,0);
Color PURPLE = Color(127,0,255);
Color PINK   = Color(255,0,127);
Color TEAL   = Color(0,255,255);
Color WHITE  = Color(255,255,255);
Color BLACK  = Color(0,0,0);
Color GRAY  = Color(127,127,127);