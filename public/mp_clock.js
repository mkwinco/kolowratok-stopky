function pad(num, size) {
	var s = "0000" + num;
	return s.substr(s.length - size);
}

function formatTime(time) {
	var h = m = s = ms = 0;
	var newTime = '';
	var style = "<span style='color:#000000'>";

	if (time < 0 ) {
		style = "<span style='color:yellow; text-decoration: blink;'> - ";
		time = -time;
	};
		
	
	h = Math.floor( time / (60 * 60 * 1000) );
	time = time % (60 * 60 * 1000);
	m = Math.floor( time / (60 * 1000) );
	time = time % (60 * 1000);
	s = Math.floor( time / 1000 );
	ms = time % 1000;

	newTime = /*pad(h, 2) + ':' + */pad(m, 2) + ':' + pad(s, 2) ;//+ '.' + pad(ms, 2);
	newTime = style + newTime + "</span>";
	return newTime;
}

var now	= function() {
	return (new Date()).getTime(); 
}; 


function loadgamenames() {
	// using alternate syntax: http://api.jquery.com/jquery.getjson/
	jQuery.getJSON("loadgamenames",null)
		.done(function(data,status) {

			var menu = jQuery("#loadmenu");
			menu.empty();
			jQuery.each(data.games, function(i,v) {

				jQuery("<option />")
					.attr("value", v.g_id)
					.text(v.name + " (" + v.last_save + ")")
					.appendTo(menu);
			  });
		}
	);
};


function start() {
	console.log("start");
	loadgamenames();
};


var clocktimer;
var frequency=100; //ms

var active = 0;
var last_start = 0;

var turntime=0;

var g;

function startgame() {

	console.log("startgame");
	//console.dir(g);
	//var c = jQuery("#Container");

// Clear any New-Game elements
	jQuery('#ng').remove();
	
// switch create game button back to new game button
	jQuery("#newgamebutton").attr({'value':"New Game", 'onclick':"javascript: newgame()"} );
	
// Clear the containers from any previous games
	jQuery("#container_players,#Container").empty();

// Create table for outpus
	var pt=jQuery("<table />")
		.attr({'id':"playertable","border":"1"})
		.css({"width":"500px","font-family": "Open Sans"})
		.append( jQuery("<tr />")
			.append( jQuery("<th />").text("Player").css({"align":"left"} ) )
			.append( jQuery("<th />").text("Time").css({"align":"center"} ) ) 
			.append( jQuery("<th />").text("Add").css({"text-align":"left"} ) ) 
			.append( jQuery("<th />").text("Spent").css({"text-align":"left"} ) ) 
			.append( jQuery("<th />").text("Score").css({"text-align":"left"} ) ) 
		)
		.appendTo( jQuery("#container_players") );
	
// Run through all players in game and prepare divs and spans for them
	jQuery.each(g.status, function(i,v) {
		
		pt.append(
			jQuery("<tr />").attr({'id':"row0"+i})
			.append( jQuery("<td />").text((1+i)+" "+v.player_name).attr({'id':"playerid"+i}).css({"align":"left"}) )
			.append( jQuery("<td />").html(formatTime(v.time_balance)).attr({'id':"time0"+i}).css({"align":"center"}) )
			.append( jQuery("<td />").append( jQuery("<select />").attr({'id':"vpselector0"+i} ) ).css({"align":"center"}) )
			.append( jQuery("<td />").text(v.spent).attr('id',"spent0"+i).css({"align":"center","fontWeight":"lighter"}) ) 
			.append( jQuery("<td />").text(v.score).attr('id',"score0"+i).css({"align":"center","fontWeight":"bold"}) )
			
		);
		var s = jQuery("#vpselector0"+i);
		jQuery.each([0,1,2,3,4,5,6,7,8,9], function(j,w) {s.append(jQuery('<option>',{value:j}).text(j))}); 
	
		
// use this loop to translate active as a name (g.active) into index (active)
		if (g.active==v.player_name) {active=i};
		console.log(active);
		
	});
// however, if turn is 0, the first player is always active
//	if (g.turn==0) {g.turn=1; active=0;}
// this was turned off - the first players extratime in turn 0 would not load correctly otherwise

// Output the header
	jQuery("<div />").html(g.name).attr('id',"gamename").css({"width":"500px","background-color":"#FFD700"}).appendTo( jQuery("#Container") );
	jQuery("<div />").html("TURN: " + g.turn).attr('id',"turntimer").appendTo( jQuery("#Container") );
	jQuery("<div />").html("Initial time: " + g.initialtime + "s<br> Extra time: " + g.extratime + "s (per turn)").appendTo( jQuery("#Container") );
	jQuery("<div />").html("TURN TIME (" + g.status[active].player_name + "): " + formatTime(turntime)).attr('id',"turntime").appendTo( jQuery("#container_players") );
	
// Active was resolved above, we can write about it (and make it bold)
	if (g.turn>0) {
		jQuery("#playerid"+active).css('fontWeight','bold');
		jQuery('<input/>').attr({ type: 'button', id:'startbutton', value:'►', onclick:"create_next_button();start_timer()"}).appendTo( jQuery("#Container") );
// in a case this is very first game turn, there is no bold player and even the button is "next" in fact (because active player is the last one)
	} else if (g.turn==0) {
		jQuery('<input/>').attr({ type: 'button', id:'startbutton', value:'►', onclick:"create_next_button();next_timer()"}).appendTo( jQuery("#Container") );
	};
	jQuery('#startbutton').css({"width":"100px","height":"70px"});
};

function loadgame(gameid) {
	
// stop anything that was running before (but handle db writting)
	stop_timer();
	console.log("loadgame: " + gameid);
	//console.dir(gameid);

	jQuery.ajax({
		url: 'loadgame',
		type: 'GET',
		dataType:'json',
		data: {"gameid":gameid}, //jQuery('#loadmenu>option:selected').val(),
		success: function(data,status) {
			g=data.game;
			//console.dir(g);
			loadgamenames()
			startgame();
		},
		error:  function(data,status) {
			alert(" GAME cannot be loaded!");
		},
	});
	
};

// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
var players = {'ingame':[],'available':[]};

function newgame() {
	
// Clear the containers from any previous games
	jQuery("#container_players,#Container").empty();
	
// switch new game button to create game button
	jQuery("#newgamebutton").attr({'value':"Create Game", 'onclick':"javascript: creategame()"} );
	
// create new container where the new game is going to be created
	jQuery('body').append(	jQuery('<div/>',{id:'ng'})	);
// inside the container, there will be init time, extra time and player-selection table
	jQuery('#ng').append("<hr><form id='timeform'>New game name: <input id='newgamename' type='text' value='New game name'><br>Initial Time [s]: <input id='inittime' type='number' min='0' step='1' value='0'><br>Extra Time [s]: <input id='extratime' type='number' min='0' step='1' value='120'></form><hr>");
		
	jQuery('#ng').append( jQuery('<table/>', {id:'pmt'}) ).append( jQuery('<tbody/>', {id:'pmtb'}) );
// this is inside table (empty so far)
	jQuery('<tr><td>In game</td><td/><td>Pick players</td></tr>').appendTo('#pmtb');
	jQuery('<tr><td> <select id="ingame" class="inputselect" style="width: 280px;" multiple="multiple" size="10"></select> </td>  <td> <input id="addplayer" type="button" onclick="move_player(\'add\');" value=" « "> <br> <input id="delplayer" type="button" onclick="move_player(\'remove\');" value=" » "> </td>  <td>  <select id="available" class="inputselect" style="width: 280px;" multiple="multiple" size="10"></select>  <form name="APform" id="APform" action="javascript:void(0);" onsubmit="AddPlayer()"> <input type="text" name="NewPlayersName"> <input type="submit" value="AddPlayer"> </form></td></tr>').appendTo('#pmtb');
	
	// and now load all the players
	jQuery.get(
		"loadplayers",
		null,
		function(data,status) {
			console.dir(data);
			players.available = data.available;
			fillout_table();
		},
		"json"
	);
};

function AddPlayer() {
	//console.log(document.forms["APform"]["NewPlayersName"].value);
	var NewPlayerName=jQuery("#APform")[0][0].value;
	//console.log(NewPlayerName);
	
	
	// send new player into DB and use him/her if added succesfully
	jQuery.ajax({
		'async': false,
		'type': "POST",
		'global': false,
		'dataType': 'json',
		'url': "addplayer",
		'data': { 'NewPlayerName': NewPlayerName },
		'success': function (data,status) {
			if (data.playersadded==1) {players.available.push(NewPlayerName);}
			if (data.playersadded==0) {alert("Player " + NewPlayerName + " exists!");}
			fillout_table();
		}
	});
};

// Two functions that fill out the selection table out of "players" variable
function fillout_players(selectid,playerslist) {
	jQuery(selectid).empty();
	jQuery.each(playerslist, function(i,v) {
		jQuery('<option />',{text:v}).appendTo(selectid);
	});
};

function fillout_table() {
	fillout_players('#ingame',players.ingame);
	fillout_players('#available',players.available);
};


// this function is bound to onclick property of the add/remove player buttons
function move_player(movetype) {
// on right click deselect: $('#mySelectList').val('');
	
	var from,to;
	if (movetype == "add") {from = 'available'; to = 'ingame';} 
	else if (movetype == "remove") {from = 'ingame'; to = 'available';};
	
// players' name(s) that is/are currently selected [array]
	jQuery('#'+from+' option:selected').each(function(i,v){
		// are removed from that list
		var scs = players[from].splice(players[from].indexOf(v.value),1);
		// and if done successfully, then they are pushed into the other list
		if (scs != -1) {players[to].push(v.value)};
	});

// and finally update the status
	fillout_table();
};


function creategame() {
	
	//console.dir(players);
	if (jQuery.isEmptyObject(players.ingame)) {alert("Select some players first"); return;};
	// now the whole info about new game is sent to db
	var newgame = {name:document.forms["timeform"]["newgamename"].value,initialtime:document.forms["timeform"]["inittime"].value, extratime:document.forms["timeform"]["extratime"].value,players:JSON.stringify(players.ingame)}
	console.dir(newgame);
	
	// send new game into DB
	jQuery.ajax({
//		'async': false,
		'type': "POST",
		'global': false,
		'dataType': 'json',
		'url': "addgame",
		'data': newgame,
		'success': function (data,status) {
			if (data.returncode < 0) {alert("Something went wrong");}
			// if all went ok and the game is in the db, then load it from there and start playing
			loadgame(String(data.returncode));
		},
		'error':  function (data,status) {alert("Something went wrong");},
	});
	
};


// ====================================================================================


function update() {
	
	var timepassed = now()-last_start;
	//console.log(timepassed);
	jQuery("#time0"+active).html(formatTime(g.status[active].time_balance - timepassed ) );
	jQuery("#turntime").html("TURN TIME (" + g.status[active].player_name + "): " + formatTime(turntime + timepassed ) );
}

function create_next_button() {
	// create next button4
	jQuery('<input/>').attr({ type: 'button', name:'next', value:'next', onclick:"javascript: next_timer()"}).css({"width":"100px","height":"70px"}).appendTo( jQuery("#Container") );
// actually, next should be available anywhere in player container area
	//jQuery("#container_players").attr('onclick', "javascript: next_timer()");
// well no, when selecting score, it's not doing any good
};

function start_timer() {
	if (last_start != 0) return; // if the time is running, unpause should do nothing

//switch stop/pause
	jQuery("#startbutton").attr({'value':"■", 'onclick':"javascript: stop_timer('timeonly')"} );
	
	clocktimer = setInterval("update()", frequency);
	last_start = now();
};

function stop_timer(what) {

	// if the time is not running, stop should do nothing
	if (last_start == 0) {
		// well that is not true, next should always update DB
		send_status_to_db(active,what);
		return; 
	};
	
	clearInterval(clocktimer);

//switch stop/pause
	jQuery("#startbutton").attr({'value':"►", 'onclick':"javascript: start_timer()"} );
	
// the active- and turn- timers should be stopped here
	var timepassed = now()-last_start;
	g.status[active].time_balance = g.status[active].time_balance - timepassed; 
	turntime = turntime + timepassed;
	
	
	send_status_to_db(active,what);
	
	last_start = 0;
};

function next_timer(){

// stop timer for the old "active" (and do it before turn is raised by 1)
	stop_timer('full');
	
	jQuery("#playerid"+active).css('fontWeight','normal');
	jQuery("#row0"+active).css('background-color','lightblue');

	var nextactive = active + 1; 
	if (nextactive >= g.status.length) {nextactive=0; g.turn++};
	
	jQuery("#turntimer").html("TURN: " + g.turn);

// pass active to the next
	active = nextactive;
// extend actual time for extratime (as each turn)
	
//	console.dir(g.status[active]);
//	console.log(g.extratime);
	g.status[active].time_balance = g.status[active].time_balance + g.extratime * 1000;
//	console.dir(g.status[active]);

	
	turntime = 0;

	jQuery("#playerid"+active).css('fontWeight','bold');
	jQuery("#row0"+active).css('background-color','orange');
// start time for new active	
	start_timer()
};



function send_status_to_db(updated,what){
// if g is undefined then no game has yet been loaded
	if (typeof g === 'undefined') return;
	
	// the new victory points should be updated ONLY when next is pressed
	var add = 0;
	if (what === 'full') {
		add = jQuery('#vpselector0'+updated+'>option:selected').val()
	}
	else if (what === 'timeonly') {
		add=0;
	};

	console.log(add);
	
// update the database
	jQuery.post(
		"updategame",
		{"player":g.status[updated], "turn":g.turn, "gamename":g.name, "gameid":g.g_id, "add":add},
		function(data,status) {
			//update only the active one
			g.status[updated]=data.game.status[updated];
			// bulletproof way would be using "forEach" player, but ....
			console.log("...updating...");
			console.dir(g.status[updated]);
			jQuery("#time0"+updated).html(formatTime(g.status[updated].time_balance));
			jQuery("#score0"+updated).text(g.status[updated].score);
			jQuery("#spent0"+updated).text(g.status[updated].spent);
		},
		"json"
	);
	
};