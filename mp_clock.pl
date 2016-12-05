#!/usr/bin/env perl


use Data::Dumper;
$Data::Dumper::Terse = 'true';
$Data::Dumper::Sortkeys = 'true';
$Data::Dumper::Sortkeys = sub { [reverse sort keys %{$_[0]}] };


use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
use Mojolicious::Command::deploy::heroku;
#app->config(hypnotoad => {listen => ['http://*:8090']});


use Mojo::Pg;
# protocol://user:pass@host/database
my $pg = Mojo::Pg->new('postgresql://postgres:postgres@localhost/kolovratok');

############ loadgamenames ##############
get '/loadgamenames' => sub  {
	my $c = shift;

	my $select = $pg->db->query(qq(SELECT g_id,name,to_char(game_last_updated_at, 'Dy, DD-Mon-YYYY HH24:MI:SS') last_save FROM testuser1.game;));
	
	my @out = ();
	while (my $next = $select->hash) {push(@out,$next);};
	
	$c->render(json => {games => \@out});
};

############ loadgame ##############
get '/loadgame' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SELECT testuser1.actual_status(?);),$c->param('gameid'));
	my $collection = $select->arrays;

	my $game = decode_json $collection->to_array->[0]->[0];
#	say Dumper($game);
	
	$c->render(json => {game => $game });
};

############ loadplayers ##############
get '/loadplayers' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SELECT name FROM testuser1.player;));

	my @out = ();
	while (my $next = $select->array) {push(@out,$next->[0])};
	#say Dumper(\@out);
	
	$c->render(json => {available => \@out });
};

############ addplayer ##############
post '/addplayer' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SELECT * FROM testuser1.addplayer(?)),$c->param('NewPlayerName'));
	# the DB function is returning just a plain number (0 or 1). It is easiest to pick it up via method "arrays" and translate to real array of arrays via "to_array"
	$c->render(json => {playersadded => $select->arrays->to_array->[0]->[0] });
};


############ addgame ##############
post '/addgame' => sub  {
	my $c = shift;
	
	# clean up incomming array and turn it into perl array
	my $aux = $c->param('players');
	$aux =~ s/^\s*\[|\"|\]\s*$//g;
	my @arr = split(/,/, $aux);
	#say Dumper(\@arr);
	#say Dumper($c->req->params->to_hash);
	
	my $select = $pg->db->query(qq(SELECT testuser1.addgame(?,?,?,?);),$c->param('name'),$c->param('initialtime'),$c->param('extratime'),\@arr);

	# the DB function is returning just a plain number (0 or 1). It is easiest to pick it up via method "arrays" and translate to real array of arrays via "to_array"
	$c->render(json => {returncode => $select->arrays->to_array->[0]->[0] });

};

############ updategame ##############
post '/updategame' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SELECT * FROM testuser1.new_turn(?,?,?,?,?)),$c->param('player[player_name]'),$c->param('player[time_balance]'),$c->param('add'),$c->param('turn'),$c->param('gamename'));
	
	$select = $pg->db->query(qq(SELECT testuser1.actual_status(?);),$c->param('gameid'));
	my $collection = $select->arrays;

	my $game = decode_json $collection->to_array->[0]->[0];
#	say Dumper($game);
	
	$c->render(json => {game => $game });
};


############ multiplayer_clock ##############
get '/multiplayer_clock' => sub {
	my $c = shift;
	
	$c->render(template => 'main');
};



app->start;
__DATA__

@@ main.html.ep
% layout 'default';
% title 'Multiplayer clock';

%= javascript "//ajax.googleapis.com/ajax/libs/jquery/1/jquery.min.js"
%= javascript "mp_clock.js"

% content;

%= javascript begin 
	start()
% end

%= input_tag 'newgamebutton', id=>'newgamebutton', type => 'button', value => 'newgame', onclick => 'newgame()'

%= select_field Load => [], (id => 'loadmenu')

%= input_tag 'Load Selected', type => 'button', value => 'loadgame', onclick => 'loadgame(jQuery(\'#loadmenu>option:selected\').val())'

%= t div => (id=>"Container") => "====================="
%= t div => (id=>"container_players", style=>'width:500px; background-color:lightblue') => "Players"



@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>