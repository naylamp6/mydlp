%%%
%%%    Copyright (C) 2010 Huseyin Kerem Cevahir <kerem@medra.com.tr>
%%%
%%%--------------------------------------------------------------------------
%%%    This file is part of MyDLP.
%%%
%%%    MyDLP is free software: you can redistribute it and/or modify
%%%    it under the terms of the GNU General Public License as published by
%%%    the Free Software Foundation, either version 3 of the License, or
%%%    (at your option) any later version.
%%%
%%%    MyDLP is distributed in the hope that it will be useful,
%%%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%%%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%%    GNU General Public License for more details.
%%%
%%%    You should have received a copy of the GNU General Public License
%%%    along with MyDLP.  If not, see <http://www.gnu.org/licenses/>.
%%%--------------------------------------------------------------------------

-module(mydlp_dynamic).

-author('kerem@medratech.com').

-export([
	load/0,
	prestart_load/0
]).

-include("mydlp.hrl").

-ifdef(__MYDLP_NETWORK).

prestart_load() ->
	load_mydlp_denied_page0().

load() ->
	load_mydlp_config(),
	load_mydlp_denied_page().

load_src(Src) ->
	try
		{Mod,Code} = dynamic_compile:from_string(Src),
		code:load_binary(Mod, "dynamic.erl", Code)
	catch
		Type:Error -> throw({dyn_compile, {Type, Error}})
	end.

denied_page_src() ->
	DPBin = case mydlp_mysql:get_denied_page() of
		Page when is_binary(Page) -> Page;
		not_found -> <<"Denied!!!">> end,
	binary_to_list(DPBin).


mydlp_denied_page_src(DeniedPageSrc) when is_list(DeniedPageSrc) ->
"-module(mydlp_denied_page).
-author('kerem@medratech.com').

-export([
	get/0,
	get_base64_str/0
]).

get() -> <<\"" ++ DeniedPageSrc ++ "\">>. 

get_base64_str() -> \"" ++ 
	binary_to_list(
		mydlp_api:insert_line_feed(
			base64:encode(DeniedPageSrc)
		)
	)
 				++ "\". 

".

load_mydlp_denied_page() -> load_src(mydlp_denied_page_src(denied_page_src())).

load_mydlp_denied_page0() -> load_src(mydlp_denied_page_src("Denied!!!")).


-endif.

-ifdef(__MYDLP_ENDPOINT).

prestart_load() -> ok.

load() -> load_mydlp_config().

-endif.

-define(CONFDEF, [
	{log_dir, string, "/var/log/mydlp/"},
	{pid_file, string, "/var/run/mydlp/mydlp.pid"},
	{ssl_cert, string, "/etc/mydlp/ssl/public.pem"},
	{ssl_key, string, "/etc/mydlp/ssl/private.pem"},
	{mysql_host, string, "localhost"},
	{mysql_port, integer, "3306"},
	{mysql_user, string, "root"},
	{mysql_password, string, ""},
	{mysql_database, string, "mydlp"},
	{mysql_pool_size, string, "2"},
	{quarantine_dir, string, "/var/lib/mydlp/quarantine/"},
	{quarantine_uid, integer, "33"},
	{quarantine_gid, integer, "33"},
	{error_action, atom, "pass"},
	{auto_distribution, boolean, "false"},
	{auto_distribution_priority, integer, "100"},
	{auto_distribution_nodes, term, "['localhost']"},
	{nlp_tr, boolean, "false"},
	{nlp_tr_kokler, string, "/usr/share/mydlp/resources/mydlp_nlp_tr_kokler.txt"},
	{smtp_helo_name, string, "mydlp.org"},
	{smtp_next_hop_host, string, "localhost"},
	{smtp_next_hop_port, integer, "10027"},
	{smtp_bypass_on_fail, boolean, "true"},
	{smtp_enable_for_all, boolean, "true"},
	{icap_reqmod_path, string, "/dlp"},
	{icap_respmod_path, string, "/dlp-respmod"},
	{icap_max_connections, integer, "0"},
	{icap_options_ttl, integer, "0"},
	{icap_log_pass, boolean, "false"},
	{icap_log_pass_lower_limit, integer, "10240"},
	{smb_discover, boolean, "false"},
	{smb_discover_script_path, string, "/usr/sbin/mydlp-smb-discover"},
	{smb_discover_interval, integer, "3600"},
	{archive_minimum_size, integer, "256"}
]).

-define(CONFIG_HEAD, "
-module(mydlp_config).
-author('kerem@mydlp.org').

-compile(export_all).

").

load_mydlp_config() -> load_src(mydlp_config_src()).

mydlp_config_src() ->
	{ok, Device} = file:open("mydlp.conf", [read]),
	ConfSrc = mydlp_config_parse(Device),
	?CONFIG_HEAD ++ ConfSrc.

mydlp_config_parse(Device) -> mydlp_config_parse(Device, ?CONFDEF, "").

mydlp_config_parse(Device, ConfDef, ConfSrc) ->
	case io:get_line(Device, "") of
		eof -> file:close(Device),
			ConfDefSrc = confdef_to_src(ConfDef),
			ConfSrc ++ ConfDefSrc;
		Line -> {ConfDef1, SLine} = line_to_src(ConfDef, Line),
			mydlp_config_parse(Device, ConfDef1, ConfSrc ++ SLine) end.

line_to_src(ConfDef, "#" ++ _Rest) -> {ConfDef, ""};
line_to_src(ConfDef, Line) ->
	case get_kv(Line) of
		none -> {ConfDef, ""};
		{KeyStr, ValStr} ->
			Key = list_to_atom(KeyStr),
			{Key, Type, _DefaultVal} = lists:keyfind(Key, 1, ConfDef),
			ValSrcStr = val_to_type_src(Type, ValStr),
			SLine = KeyStr ++ "() -> " ++ ValSrcStr ++ ".\r\n",
			ConfDef1 = lists:keydelete(Key, 1, ConfDef),
			{ConfDef1, SLine} end.

get_kv(Line) -> get_kv(Line, {"", false, false}, {"", false, false}).

%get_kv(Line, {Key, IsStarted, IsFinished}, {Val, IsStarted, IsFinished})
get_kv([$#|_Rest], {_Key, false, false}, {_Val, false, false}) -> none;
get_kv([$\r|_Rest], {_Key, false, false}, {_Val, false, false}) -> none;
get_kv([$\n|_Rest], {_Key, false, false}, {_Val, false, false}) -> none;
get_kv([$\s|Rest], {Key, false, false}, {Val, false, false}) -> get_kv(Rest, {Key, false, false}, {Val, false, false});
get_kv([$\t|Rest], {Key, false, false}, {Val, false, false}) -> get_kv(Rest, {Key, false, false}, {Val, false, false});
get_kv([C|Rest], {Key, false, false}, {Val, false, false}) -> get_kv(Rest, {[C|Key], true, false}, {Val, false, false});
get_kv([$\s|Rest], {Key, true, false}, {Val, false, false}) -> get_kv(Rest, {Key, true, true}, {Val, false, false});
get_kv([$\t|Rest], {Key, true, false}, {Val, false, false}) -> get_kv(Rest, {Key, true, true}, {Val, false, false});
get_kv([C|Rest], {Key, true, false}, {Val, false, false}) -> get_kv(Rest, {[C|Key], true, false}, {Val, false, false});
get_kv([$\s|Rest], {Key, true, true}, {Val, false, false}) -> get_kv(Rest, {Key, true, true}, {Val, false, false});
get_kv([$\t|Rest], {Key, true, true}, {Val, false, false}) -> get_kv(Rest, {Key, true, true}, {Val, false, false});
get_kv([C|Rest], {Key, true, true}, {Val, false, false}) -> get_kv(Rest, {Key, true, true}, {[C|Val], true, false});
get_kv([$#|Rest], {Key, true, true}, {Val, true, false}) -> get_kv(Rest, {Key, true, true}, {Val, true, true});
get_kv([$\r|Rest], {Key, true, true}, {Val, true, false}) -> get_kv(Rest, {Key, true, true}, {Val, true, true});
get_kv([$\n|Rest], {Key, true, true}, {Val, true, false}) -> get_kv(Rest, {Key, true, true}, {Val, true, true});
get_kv([C|Rest], {Key, true, true}, {Val, true, false}) -> get_kv(Rest, {Key, true, true}, {[C|Val], true, false});
get_kv(_, {Key, true, true}, {Val, true, true}) -> get_kv_ret(Key, Val);
get_kv([], _, _) -> none.

get_kv_ret(Key, Val) ->
	KeyF = lists:reverse(Key),
	Val1 = lists:reverse(Val),
	Val2 = strip_ws(Val1),
	ValF = string:strip(Val2, both, $"),
	{KeyF, ValF}.

strip_ws(String) ->
	S1 = string:strip(String),
	S2 = string:strip(S1, both, $\t),
	case String of
		S2 -> String;
		_Else -> strip_ws(S2) end.
	

val_to_type_src(boolean, "yes") -> "true";
val_to_type_src(boolean, "y") -> "true";
val_to_type_src(boolean, "true") -> "true";
val_to_type_src(boolean, "no") -> "false";
val_to_type_src(boolean, "n") -> "false";
val_to_type_src(boolean, "false") -> "false";
val_to_type_src(string, V) -> "\"" ++ V ++ "\"";
val_to_type_src(integer, V) -> V;
val_to_type_src(atom, V) -> V;
val_to_type_src(term, V) -> V.

confdef_to_src(ConfDef) -> confdef_to_src(ConfDef, "").

confdef_to_src([{Key, Type, ValStr}| RestDef], Acc) ->
	KeyStr = atom_to_list(Key),
	ValSrcStr = val_to_type_src(Type, ValStr),
	SLine = KeyStr ++ "() -> " ++ ValSrcStr ++ ".\r\n",
	confdef_to_src(RestDef, Acc ++ SLine);
confdef_to_src([], Acc) -> Acc.





