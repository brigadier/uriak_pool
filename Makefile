IGNORE_DEPS = edown eper eunit_formatters meck node_package rebar_lock_deps_plugin rebar_vsn_plugin reltool_util


DEPS += riakc
dep_riakc = git git://github.com/brigadier/riak-erlang-client master
DEPS += poolboy
dep_poolboy = git git://github.com/devinus/poolboy master
DEPS += parse_trans
dep_parse_trans = git git://github.com/esl/parse_trans.git master
COMPILE_FIRST += riak_pool_parse_trans


rebar_dep: preprocess pre-deps deps pre-app app

preprocess::

pre-deps::

pre-app::

include erlang.mk
