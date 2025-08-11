type varname = string

val extract_string_variable_or :
  ?k:(string -> string) ->               (** An optional continuation *)
  ?unsuitable_value:(string -> bool) ->  (** Filter unsuitable values *)
  default:string ->                      (** The default value, if the variable is undeclared or its value unsuitable *)
  varname -> string                      (** The name of the variable *)

val extract_bool_variable_or :
  default:bool ->                        (** The default value, if the variable is undeclared or its value unsuitable *)
  varname -> bool                        (** The name of the variable *)

val get_string_variable :
  ?k:(string -> string option) ->        (** An optional continuation, applied with Option.bind *)
  ?unsuitable_value:(string -> bool) ->  (** Filter unsuitable values *)
  varname -> string option               (** The name of the variable *)

type source = [ `Filename of string | `Environment ] (* = Configuration_files.source *)

val get_string_variable_with_source :
  ?k:(string * source -> (string * source) option) ->  (** An optional continuation, applied with Option.bind *)
  ?unsuitable_value:(string * source -> bool) ->       (** Filter unsuitable values *)
  varname ->                                           (** The name of the variable *)
    (string * source) option
