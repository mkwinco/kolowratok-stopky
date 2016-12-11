#!/usr/bin/env perl


use Data::Dumper;
$Data::Dumper::Terse = 'true';
$Data::Dumper::Sortkeys = 'true';
$Data::Dumper::Sortkeys = sub { [reverse sort keys %{$_[0]}] };


use Mojolicious::Lite;
use Mojo::JSON qw(decode_json encode_json);
#app->config(hypnotoad => {listen => ['http://*:8090']});

say Dumper(\%ENV);

use Mojo::Pg;
# now we need to use $DATABASE_URL in heroku
my $pg_conn = qq();
if (! defined $ENV{'DATABASE_URL'}) {
	# if there is no such variable then run locally
	$pg_conn = 'postgresql://postgres:postgres@localhost/kolovratok';
} else {
	# use the variable
	$pg_conn = $ENV{'DATABASE_URL'};
};
# however, protocol for Mojo::Pg is postgresql, not postgres as Heroku gives
$pg_conn =~ s/^postgres:/postgresql:/;

# protocol://user:pass@host/database
my $pg = Mojo::Pg->new($pg_conn);

######## add authentication ##########
plugin 'authentication', {
	autoload_user=>1,
	load_user => sub {
		my ($c,$uid) = @_;
		return $uid;
	},
	validate_user => sub {
		my ($c,$un,$pw,$extra) = @_;
		
		my $authDB = $pg->db->query(qq(SELECT * FROM general.authenticate(?,?,?);),$un,$pw,'')->hash;
		
		say Dumper($authDB);

		# if there is authenticated user and the username equals the incoming value then return it
		if (defined $authDB->{'authenticate'}) {
			return $authDB->{'authenticate'} if ($authDB->{'authenticate'} eq $un)
		};
		# otherwise return undef
		return;
	},
};

############## LOGIN ##################
post '/login_test' => sub {
	my $c = shift;
	
	my $u=$c->authenticate($c->req->param('username'),$c->req->param('password'),{auth_key=>''});
	$c->redirect_to('/');

};


get '/login/:info' => [info => [qw/ denied login /]] => sub {
	my $c = shift;
	
	$c->logout();
	$c->render('login');
  
};


post '/adduser' => sub {
	my $c = shift;
	
	my $create = $pg->db->query(qq(SELECT general.add_user(?,general.hashme(?),?);), $c->req->param('username'),$c->req->param('password') ,'' )->hash;
	
	my $u=$c->authenticate($c->req->param('username'),$c->req->param('password'),{auth_key=>''});
	$c->redirect_to('/');

};

get '/createuser' => sub {
	my $c = shift;

	$c->render('createuser');
  
};
####################### UNDER (NOT AUTENTICATED) ########################
under sub {
	my $c = shift;
	
	return 1 if ($c->is_user_authenticated());
	
	$c->redirect_to('login/denied');
	return;
};


############ loadgamenames ##############
get '/loadgamenames' => sub  {
	my $c = shift;

	my $select = $pg->db->query(qq(SET search_path TO ?; SELECT g_id,name,to_char(game_last_updated_at, 'Dy, DD-Mon-YYYY HH24:MI:SS') last_save FROM game;),$c->current_user());
	
	my @out = ();
	while (my $next = $select->hash) {push(@out,$next);};
	
	$c->render(json => {games => \@out});
};

############ loadgame ##############
get '/loadgame' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SET search_path TO ?; SELECT actual_status(?);),$c->current_user(),$c->param('gameid'));
	my $collection = $select->arrays;

	my $game = decode_json $collection->to_array->[0]->[0];
#	say Dumper($game);
	
	$c->render(json => {game => $game });
};

############ loadplayers ##############
get '/loadplayers' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SET search_path TO ?; SELECT name FROM player;),$c->current_user());

	my @out = ();
	while (my $next = $select->array) {push(@out,$next->[0])};
	#say Dumper(\@out);
	
	$c->render(json => {available => \@out });
};

############ addplayer ##############
post '/addplayer' => sub  {
	my $c = shift;
	
	my $select = $pg->db->query(qq(SET search_path TO ?; SELECT * FROM addplayer(?)),$c->current_user(),$c->param('NewPlayerName'));
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
	
	my $select = $pg->db->query(qq(SET search_path TO ?; SELECT addgame(?,?,?,?);),$c->current_user(),$c->param('name'),$c->param('initialtime'),$c->param('extratime'),\@arr);

	# the DB function is returning just a plain number (0 or 1). It is easiest to pick it up via method "arrays" and translate to real array of arrays via "to_array"
	$c->render(json => {returncode => $select->arrays->to_array->[0]->[0] });

};

############ updategame ##############
post '/updategame' => sub  {
	my $c = shift;
	
	#say Dumper($c->req->params->to_hash);
	my $select = $pg->db->query(qq(SET search_path TO ?; SELECT * FROM new_turn(?,?,?,?,?)),$c->current_user(),$c->param('player[player_name]'),$c->param('player[time_balance]'),$c->param('add'),$c->param('turn'),$c->param('gamename'));
	
	$select = $pg->db->query(qq(SET search_path TO ?;SELECT actual_status(?);),$c->current_user(),$c->param('gameid'));
	my $collection = $select->arrays;

	my $game = decode_json $collection->to_array->[0]->[0];
#	say Dumper($game);
	
	$c->render(json => {game => $game });
};


############ multiplayer_clock ##############
get '/' => sub {
	my $c = shift;

	$c->render(template => 'main', user => $c->current_user());
};


app->start;
############################################### DATA #####################################################
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

%= t div => (id=>"user") => "Logged in user: ".$user
%= input_tag 'logout', id=>'logout', type => 'button', value => 'logout', onclick=>"location.href= '/login/login';"
<br>
%= input_tag 'newgamebutton', id=>'newgamebutton', type => 'button', value => 'newgame', onclick => 'newgame()'

%= select_field Load => [], (id => 'loadmenu')

%= input_tag 'Load Selected', type => 'button', value => 'loadgame', onclick => 'loadgame(jQuery(\'#loadmenu>option:selected\').val())'

%= t div => (id=>"Container") => "====================="
%= t div => (id=>"container_players", style=>'width:500px; background-color:lightblue') => "Players"



@@ login.html.ep
% layout 'default';
% title 'Multiplayer clock login';


%= t h1 => 'Multiplayer clock login'
%== $info
%= form_for '/login_test' => (method => 'post') => begin
	<table>
		<tr> <td>Username: </td> <td> <%= text_field 'username' %> </td> </tr>
		<tr> <td>Password: </td> <td> <%= text_field 'password' %> </td> </tr>
	</table>
	%= submit_button 'Log in'
%= end
<a href="<%= url_for 'createuser' %>">Create user with new userspace</a>


@@ createuser.html.ep
% layout 'default';
% title 'Multiplayer clock create user';
%= t h1 => 'Create new userspace'
%= form_for '/adduser' => (method => 'post') => begin
	<table>
		<tr> <td>Username: </td> <td> <%= text_field 'username' %> </td> </tr>
		<tr> <td>Password: </td> <td> <%= text_field 'password' %> </td> </tr>
	</table>
	%= submit_button 'Create new user'
%= end
<a href="<%= url_for 'login/login' %>">Log in existing user</a>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>