enum tracking_modes {
	MODE_FULL,	 // player name tags shown through walls
	MODE_LOCAL,  // player name tags shown on visible players only. No dots.
	MODE_SIMPLE  // player dots shown through walls
}

class PlayerState
{
	EHandle plr;
	dictionary targetPlrs; // player state keys
	CScheduledFunction@ interval; // handle to the interval
	bool enabled = false;
	bool filteredTracking = false;
	int updateRate = 1;
	int mode = MODE_FULL;
	bool hidden = false;
}
 

// persistent-ish player data, organized by steam-id or username if on a LAN server, values are @PlayerState
dictionary player_states;
bool abort_updates = false;

string font_sprite = "sprites/as_lost/consolas96.spr";
int maxNameLength = 16;

CCVar@ cvar_disabled;

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
	
	@cvar_disabled = CCVar("disabled", 0, "disables tracking", ConCommandFlag::AdminOnly);
	
	init();
}

void MapInit()
{
	g_Game.PrecacheModel(font_sprite);
	abort_updates = false;
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

void displayText(Vector pos, CBasePlayer@ observer, CBaseEntity@ plr, string text, float scale, int life, bool dot_only)
{
	if (dot_only) {
		text = "O";
	}
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
	float charHeight = 18.0f*scale;
	pos.z += charHeight*lines.length()*0.5f;
	
	if (dot_only) {
		charWidth = charHeight = 32.0f;
	}
	
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
	
	if (dot_only) {
		te_sprite(pos, "sprites/glow01.spr", int(scale*10), 255, MSG_ONE_UNRELIABLE, observer.edict());
		return;
	}
	
	Vector beamCharExtent = newlineAxis*charHeight*0.5f;
	int beamWidth = int(charWidth*4);
	float y = 0;
	for (uint k = 0; k < lines.length(); k++)
	{
		float x = -float(lines[k].Length() * charWidth) / 2.0f;
		x += charWidth * 0.5f;

		for (uint i = 0; i < lines[k].Length(); i++)
		{
			int c = int(lines[k][i]) - 32;			
			if (c == 0) {
				continue; // don't render spaces
			} else if (c < 0 || c > 94) {
				c = 0; // show unknown char
			}
			
			Vector charPos = pos + textAxis*x + newlineAxis*y;

			te_beampoints(charPos - beamCharExtent, charPos + beamCharExtent, font_sprite, c, 0, life, beamWidth, 0, WHITE, 0, MSG_ONE_UNRELIABLE, observer.edict());
			
			x += charWidth;
		}

		y += charHeight;
	}
}

// display name overhead
void showNameTag(CBasePlayer@ observer, CBaseEntity@ target, PlayerState@ state, bool dot_only, bool visible_only)
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
		if (!dot_only) {
			pos = target.pev.origin;
			pos.z += 50.0f;
			dstr = "";
			displayText(pos, observer, target, dstr + name, 0.2f, state.updateRate, false);
		}
	}
	else if (!visible_only)
	{		
		pos = observer.pev.origin + delta.Normalize()*maxDist*0.99f;
		
		if (bodySight)
		{
			dstr = "";
			pos.z += 15.0f;
		}
		else
			pos.z += 20.0f;
		
		displayText(pos, observer, target, dstr + name, 0.2f, state.updateRate, dot_only);
	}
}

class LostTarget {
	CBaseEntity@ target;
	float observerDot; // how closely the target aligns with the observer's center of view
}

void helpLostPlayer(EHandle h_plr)
{
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null) {
		return;
	}
	
	PlayerState@ observerState = getPlayerState(plr);
	Math.MakeVectors( plr.pev.v_angle );
	Vector lookDir = g_Engine.v_forward;
	lookDir.Normalize();
	array<LostTarget> targets; // players most in line with the observers view (should get name tags)

	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		CBasePlayer@ target = cast<CBasePlayer@>(state.plr.GetEntity());
		if (target is null or !target.IsConnected() or target.entindex() == plr.entindex())
			continue;
		if (observerState.filteredTracking and !observerState.targetPlrs.exists(stateKeys[i]))
			continue;
		if (state.hidden) {
			if (observerState.filteredTracking) {
				observerState.targetPlrs.delete(stateKeys[i]);
				g_PlayerFuncs.SayText(plr, "" + target.pev.netname + " is now hiding and can't be tracked.\n");
			}
			continue;
		}
		
		Vector delta = (target.pev.origin - plr.pev.origin).Normalize();
		
		LostTarget lostTarget;
		@lostTarget.target = @target;
		lostTarget.observerDot = DotProduct(lookDir, delta);
		
		targets.insertLast(lostTarget);
	}
	
	if (observerState.mode != MODE_SIMPLE) {
		if (targets.size() > 0) {
			targets.sort(function(a, b) {		
				return a.observerDot > b.observerDot; 
			});
		}
	}
	
	for (uint i = 0; i < targets.size(); i++) {
		if (i < 3 && observerState.mode != MODE_SIMPLE) {
			showNameTag(plr, targets[i].target, observerState, false, observerState.mode == MODE_LOCAL);
		} else if (observerState.mode != MODE_LOCAL) {
			showNameTag(plr, targets[i].target, observerState, true, false);
		}
	}
	
	//for (int i = 0)
	
	if (observerState.enabled && cvar_disabled.GetInt() == 0) {
		float rate = Math.max(observerState.updateRate / 10.0f, 0.1f);
		g_Scheduler.SetTimeout("helpLostPlayer", rate, h_plr);
	}
}

string getPlayerUniqueId(CBasePlayer@ plr)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'STEAM_ID_BOT' or steamId == 'BOT') {
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
			if (cvar_disabled.GetInt() != 0) {
				g_PlayerFuncs.SayText(plr, "Player tracking is disabled on this map.\n");
				return true;
			}
			CBasePlayer@ targetPlr = null;
			if ( args.ArgC() >= 3 && args[1] == "delay" ) {				
				int newRate = atoi(args[2]);
				
				newRate = Math.min(10, newRate);
				newRate = Math.max(1, newRate);
				
				g_PlayerFuncs.SayText(plr, "Update delay set to " + newRate + "\n");
				
				state.updateRate = newRate;
				return true;
			}
			
			if ( args.ArgC() >= 3 && args[1] == "hide" ) {
				state.hidden = atoi(args[2]) != 0;
				
				if (state.hidden) {
					g_PlayerFuncs.SayText(plr, "You are now hidden. No one can track you.\n");
				} else {
					g_PlayerFuncs.SayText(plr, "You are now visible. Anyone can track you.\n");
				}
				
				return true;
			}
			
			if ( args.ArgC() >= 3 && args[1] == "mode" ) {				
				string mode = args[2].ToLowercase();
				
				if (mode == "full") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to FULL. Name tags shown for all players.\n");
					state.mode = MODE_FULL;
				} else if (mode == "local") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to LOCAL. Name tags shown for visible players only.\n");
					state.mode = MODE_LOCAL;
				} else if (mode == "simple") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to SIMPLE. Dots shown for invisible players.\n");
					state.mode = MODE_SIMPLE;
				} else {
					g_PlayerFuncs.SayText(plr, "Unknown mode. Must be FULL, SIMPLE, or LOCAL\n");
				}
				
				return true;
			}
			
			if ( args.ArgC() >= 2 )
			{
				@targetPlr = getPlayer(plr, args[1]);
				if (targetPlr is null)
					return true;
				if (targetPlr.entindex() == plr.entindex())
				{
					g_PlayerFuncs.SayText(plr, "Can't track yourself!\n");
					return true;
				}
			}
			
			if (state.enabled and targetPlr is null)
			{
				g_PlayerFuncs.SayText(plr, "Player tracking disabled\n");
				state.targetPlrs.deleteAll();
				state.enabled = false;
				return true;
			}
			
			if (targetPlr !is null) {
				PlayerState@ targetState = getPlayerState(targetPlr);
				
				if (targetState.hidden) {
					g_PlayerFuncs.SayText(plr, "" + targetPlr.pev.netname + " is hiding and can't be tracked.\n");
					return true;
				}
			
				state.filteredTracking = true;
				
				string targetId = getPlayerUniqueId(targetPlr);
				if (state.targetPlrs.exists(targetId)) {
					state.targetPlrs.delete(targetId);
					g_PlayerFuncs.SayText(plr, "Tracking disabled for player " + targetPlr.pev.netname + "\n");
				} else {
					state.targetPlrs[targetId] = true;
					g_PlayerFuncs.SayText(plr, "Tracking player " + targetPlr.pev.netname + "\n");
				}
			}
			else {
				state.filteredTracking = false;
				g_PlayerFuncs.SayText(plr, "Player tracking enabled\n");
			}
			
			if (!state.enabled) {
				state.enabled = true;
				g_Scheduler.SetTimeout("helpLostPlayer", 0.0f, EHandle(plr));
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