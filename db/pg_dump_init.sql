--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.1
-- Dumped by pg_dump version 9.6.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: general; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA general;


ALTER SCHEMA general OWNER TO postgres;

SET search_path = general, pg_catalog;

--
-- Name: actual_status(name, integer); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION actual_status(sch name, gid integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	out text;
	turn integer;
	r RECORD;
	rtext text;
	active text;
BEGIN

-- check existence of the schema
	if NOT (SELECT * FROM general.schemaexists(sch)) THEN return ''; END if;
	EXECUTE 'SET search_path TO ' ||  sch;

-- This is just the "plain" section directly from game table
SELECT row_to_json(t) INTO OUT FROM game AS t WHERE g_id=gid;
-- And remove trailing '}', we are planning to add something to the output.
out := trim( trailing '}' FROM out);

-- We are planning to use the result of this select a few times over, therefore we prepare a temporary table
-- The table contains last status of each player for the given game (gid)
CREATE TEMPORARY TABLE last_player_status ON COMMIT DROP AS 
	SELECT turn_no, player_name, time_balance, score, spent, order_in_game FROM
			(SELECT max(turn_no) as turn_no,t.pig_id,player_name,pig.order_in_game,pig.score,pig.spent FROM turn t, player_in_game pig WHERE game_id=gid AND t.pig_id=pig.pig_id GROUP BY t.pig_id,player_name,pig.order_in_game,pig.score,pig.spent) AS f
		NATURAL JOIN
			turn;

-- The highest turn number is the current turn
SELECT max(turn_no) INTO turn FROM last_player_status;

-- Active player is the last one (in game order) which is still in max turn. 
-- Go through the last player statuses ordered from first to last and when first player with less then latest turn is found, runaway
-- If all players are in the same turn => last player is active
FOR r IN 
	SELECT * FROM last_player_status ORDER BY order_in_game ASC
LOOP
	IF (turn = r.turn_no) THEN active:=r.player_name; ELSE exit; END IF;
	
END LOOP;	
-- NOTE: In case all players are in turn zero, game was not yet started

out := OUT || ',"turn":' || turn || ',"active":"' || active || '","status":[';


FOR rtext IN 
	SELECT row_to_json(t) FROM (SELECT player_name, time_balance, score, spent FROM last_player_status ORDER BY order_in_game ASC) AS t 
LOOP
	out := out  ||  rtext  ||  ',';
END LOOP;

out := trim( trailing ',' FROM out) || ']}';

	--DROP TABLE last_player_status;

	RETURN out;
END
$$;


ALTER FUNCTION general.actual_status(sch name, gid integer) OWNER TO postgres;

--
-- Name: add_user(text, uuid, text); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION add_user(un text, pw uuid, ak text DEFAULT ''::text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
BEGIN

----------------- CREATE USER SPACE -------------
-- check existence of the schema
	if (SELECT * FROM general.schemaexists(un)) THEN return false; END if;
	EXECUTE 'CREATE SCHEMA ' || un;

	EXECUTE 'SET search_path TO ' ||  un;


-- ---------------- TABLES -------------

----- game -----
	CREATE TABLE game
	(
		  g_id serial NOT NULL PRIMARY KEY,
		  name text NOT NULL UNIQUE,
		  initialtime integer NOT NULL DEFAULT 0,
		  extratime integer NOT NULL DEFAULT 120, -- Time for each turn (in seconds)
		  created_at timestamp with time zone NOT NULL,
		  game_last_updated_at timestamp with time zone
	);
	CREATE TRIGGER set_game_create_timestamp
		  BEFORE INSERT
		  ON game
		  FOR EACH ROW
		  EXECUTE PROCEDURE general.set_game_create_timestamp();

------ player -----
	CREATE TABLE player
	(
		  name text NOT NULL PRIMARY KEY
	);

------ player_in_game -----
	CREATE TABLE player_in_game
	(
	  pig_id serial NOT NULL PRIMARY KEY,
	  game_id integer NOT NULL REFERENCES game (g_id),
	  player_name text NOT NULL REFERENCES player (name),
	  order_in_game integer NOT NULL DEFAULT 1,
	  score smallint DEFAULT 0,
	  spent smallint DEFAULT 0,
	  UNIQUE (game_id, order_in_game),
	  UNIQUE (game_id, player_name)
	);
	CREATE TRIGGER turn_zero
		AFTER INSERT
		ON player_in_game
		FOR EACH ROW
		EXECUTE PROCEDURE general.turn_zero();

------ turn -----
	CREATE TABLE turn
	(
		turn_id serial NOT NULL PRIMARY KEY,
		pig_id integer NOT NULL REFERENCES player_in_game,
		turn_no integer NOT NULL,
		time_balance integer NOT NULL, -- How much time left after turn (in sec)
		UNIQUE (pig_id, turn_no)
	);
	CREATE TRIGGER touch_game
		  BEFORE INSERT OR UPDATE
		  ON turn
		  FOR EACH ROW
		  EXECUTE PROCEDURE general.touch_game();
------ passwd --------
	CREATE TABLE passwd
	(
		  username name NOT NULL PRIMARY KEY,
		  passwd uuid NOT NULL,
		  auth_key text
	);


------------------ PASSWD --------------------
-- And finally put the authentificaton data in
	EXECUTE 'INSERT INTO passwd(username,passwd,auth_key) VALUES ($1,$2,$3)' USING un,pw,ak;

	return true;


END;
$_$;


ALTER FUNCTION general.add_user(un text, pw uuid, ak text) OWNER TO postgres;

--
-- Name: addgame(name, text, integer, integer, text[]); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION addgame(sch name, n text, initt integer, extrat integer, players text[]) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
	added integer;
	addedplayers integer:=0;
	i INTEGER;
	gid integer;
	pl TEXT;
BEGIN

-- check existence of the schema
	if NOT (SELECT * FROM general.schemaexists(sch)) THEN return -3; END if;
	EXECUTE 'SET search_path TO ' ||  sch;
	

	begin
	EXECUTE 'INSERT INTO game(NAME, initialtime, extratime) VALUES ($1,$2,$3)' USING n,initt,extrat;
	GET DIAGNOSTICS added = ROW_COUNT;

	EXCEPTION WHEN 
		OTHERS
	THEN 
		RAISE EXCEPTION '-1';

	END;

	SELECT g_id INTO gid FROM game WHERE game.name=n;

	RAISE NOTICE 'Game id is %',gid;

	i:=0; -- index in the array - otherwise the order in the game
	FOREACH pl IN ARRAY players LOOP
		i:=i+1;
		BEGIN
			RAISE NOTICE 'Player name: %, order in game: % ',pl,i;
			EXECUTE 'INSERT INTO player_in_game(game_id, player_name, order_in_game) VALUES ($1,$2,$3)' USING gid,pl,i;
			GET DIAGNOSTICS added = ROW_COUNT;
			addedplayers := addedplayers + added;
			RAISE NOTICE 'added: %',added;
		EXCEPTION WHEN OTHERS
		THEN
				RAISE EXCEPTION '-2';
		END;	

	END LOOP;

	return gid;

END;
$_$;


ALTER FUNCTION general.addgame(sch name, n text, initt integer, extrat integer, players text[]) OWNER TO postgres;

--
-- Name: addplayer(name, text); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION addplayer(sch name, n text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
	added integer;
BEGIN

-- check existence of the schema
	if NOT (SELECT * FROM general.schemaexists(sch)) THEN return -1; END if;
	EXECUTE 'SET search_path TO ' ||  sch;

EXECUTE 'INSERT INTO player(name) VALUES ($1)' USING n;
GET DIAGNOSTICS added = ROW_COUNT;

RETURN added;
EXCEPTION
	WHEN unique_violation THEN RETURN 0;

END;$_$;


ALTER FUNCTION general.addplayer(sch name, n text) OWNER TO postgres;

--
-- Name: authenticate(name, text, text); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION authenticate(sch name, pw text, ak text DEFAULT ''::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE

BEGIN

-- check existence of the schema
	if NOT (SELECT * FROM general.schemaexists(sch)) THEN return NULL; END if;
	EXECUTE 'SET search_path TO ' ||  sch;

-- if auth_key provided, use it for authentication (RETURN either the username or null)
	IF (ak != '') THEN RETURN (SELECT p.username FROM (SELECT * FROM passwd where username=sch LIMIT 1) AS p WHERE p.auth_key=ak); END IF;

-- find if the password match
	RETURN (SELECT p.username FROM (SELECT * FROM passwd where username=sch LIMIT 1) AS p WHERE p.passwd = general.hashme(pw));

END;
$$;


ALTER FUNCTION general.authenticate(sch name, pw text, ak text) OWNER TO postgres;

--
-- Name: hashme(text); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION hashme(p text) RETURNS uuid
    LANGUAGE sql
    AS $$

SELECT md5(p)::uuid;

$$;


ALTER FUNCTION general.hashme(p text) OWNER TO postgres;

--
-- Name: new_turn(name, text, integer, integer, integer, text); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION new_turn(sch name, playername text, tb integer DEFAULT 0, sc integer DEFAULT 0, t integer DEFAULT 0, gamename text DEFAULT 'default'::text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
	pig integer;
	tid INTEGER;
	method text;
	added integer;
BEGIN
	-- check existence of the schema
	if NOT (SELECT * FROM general.schemaexists(sch)) THEN return '{"lines_added":"0", "error":"no such schema"}'; END if;
	EXECUTE 'SET search_path TO ' ||  sch;


	SELECT pig_id into pig FROM player_in_game AS tpig, game AS tg 
			WHERE
		gamename = tg.name 
			AND
		tpig.player_name = playername
			AND
		tpig.game_id = tg.g_id;

	-- update score
	UPDATE player_in_game SET score=score+sc, spent=spent+sc*sc WHERE pig_id=pig;

	SELECT turn_id INTO tid FROM turn 
			WHERe 
		pig_id = pig 
			AND
		turn_no =  t;

	-- If there is such row, then update it, otherwise insert new
	IF (FOUND) THEN
		UPDATE turn SET time_balance=tb
				WHERe 
			pig_id = pig 
				AND
			turn_no =  t;
-- something for the output
		GET DIAGNOSTICS added = ROW_COUNT;
		method := 'update';
	ELSE
		EXECUTE 'INSERT INTO turn(pig_id, turn_no, time_balance)
			VALUES ($1,$2,$3)' 
			USING pig, t, tb;
-- something for the output
		GET DIAGNOSTICS added = ROW_COUNT;
		method := 'insert';
	END IF;

	RETURN '{"lines_added":"' || added::text || '", "method":"' || method || '"}';
		
END;$_$;


ALTER FUNCTION general.new_turn(sch name, playername text, tb integer, sc integer, t integer, gamename text) OWNER TO postgres;

--
-- Name: schemaexists(name); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION schemaexists(sch name) RETURNS boolean
    LANGUAGE sql
    AS $$

-- faster way 
SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = sch);

-- purist way 
-- SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = sch);

$$;


ALTER FUNCTION general.schemaexists(sch name) OWNER TO postgres;

--
-- Name: set_game_create_timestamp(); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION set_game_create_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	NEW.created_at := now();
	RETURN NEW;
END;$$;


ALTER FUNCTION general.set_game_create_timestamp() OWNER TO postgres;

--
-- Name: touch_game(); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION touch_game() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
	EXECUTE 'SET search_path TO ' ||  TG_TABLE_SCHEMA;

	UPDATE testuser1.game SET game_last_updated_at=now() WHERE g_id IN 
		(SELECT game_id FROM testuser1.player_in_game WHERE pig_id=NEW.pig_id);
	RETURN NEW;
END;$$;


ALTER FUNCTION general.touch_game() OWNER TO postgres;

--
-- Name: turn_zero(); Type: FUNCTION; Schema: general; Owner: postgres
--

CREATE FUNCTION turn_zero() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
	starttime integer;
BEGIN
	EXECUTE 'SET search_path TO ' ||  TG_TABLE_SCHEMA;
	
	SELECT initialtime INTO starttime FROM game WHERE g_id=NEW.game_id;
	INSERT INTO turn(pig_id, turn_no, time_balance) VALUES (NEW.pig_id, 0, starttime*1000);

	RETURN NEW;
END;$$;


ALTER FUNCTION general.turn_zero() OWNER TO postgres;

--
-- PostgreSQL database dump complete
--

