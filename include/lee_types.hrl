-ifndef(LEE_TYPES_HRL).
-define(LEE_TYPES_HRL, true).

-import(lee_types, [ union/2
                   , union/1
                   , boolean/0
                   , term/0
                   , any/0
                   , integer/0
                   , non_neg_integer/0
                   , range/2
                   , float/0
                   , atom/0
                   , binary/0
                   , list/0
                   , list/1
                   , nonempty_list/1
                   , string/0
                   , tuple/0
                   , tuple/1
                   , map/2
                   , exact_map/1
                   , number/0
                   ]).

-compile({parse_transform, lee_transform}).

-endif.
