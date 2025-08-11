(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2010  Jean-Vincent Loddo
   Copyright (C) 2010  Université Paris 13

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. *)


(** "Switch" component implementation. *)

#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module StringExtra = Ocamlbricks.StringExtra
module Option = Ocamlbricks.Option
module Either = Ocamlbricks.Either
module OoExtra = Ocamlbricks.OoExtra
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
module Network = Ocamlbricks.Network
(* --- *)
open Gettext

(* Switch related constants: *)
(* TODO: make it configurable! *)
module Const = struct
 let port_no_default = 4
 let port_no_min = 4
 let port_no_max = 16

 let initial_content_for_rcfiles =
"# ===== FAST SPANNING TREE COMMANDS
# fstp/setfstp 0/1             Fast spanning tree protocol 1=ON 0=OFF
# fstp/setedge VLAN PORT 1/0   Define an edge port for a vlan 1=Y 0=N
# fstp/bonus   VLAN PORT COST  set the port bonus for a vlan
# ===== PORT STATUS COMMANDS
# port/sethub  0/1             1=HUB 0=switch
# port/setvlan PORT VLAN       assign PORT to VLAN (untagged port)
# ===== VLAN MANAGEMENT COMMANDS
# vlan/create  VLAN            create the vlan VLAN
# vlan/remove  VLAN            remove the vlan VLAN
# vlan/addport VLAN PORT       add PORT to the VLAN's trunk (tagged)
# vlan/delport VLAN PORT       remove PORT from the VLAN's trunk
" ;;

end

(* The type of data exchanged with the dialog: *)
module Data = struct
type t = {
  name              : string;
  label             : string;
  port_no           : int;
  show_vde_terminal : bool;
  activate_fstp     : bool;
  rc_config         : bool * string; (* run commands (rc) file configuration *)
  old_name          : string;
  }

let to_string t = "<obj>" (* TODO? *)
end (* Data *)

module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.switch.palette.png"
   let tooltip   = (s_ "Switch")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._S

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "S" in
      Dialog_add_or_update.make ~title:(s_ "Add switch") ~name ~ok_callback ()

    let reaction
       { name = name; label = label; port_no = port_no;
         show_vde_terminal = show_vde_terminal; activate_fstp = activate_fstp;
         rc_config = rc_config; _ }
      =
      let action () =
        ignore
          (new User_level_switch.switch
                 ~network:st#network ~name ~label ~port_no ~show_vde_terminal ~activate_fstp ~rc_config ())
      in
      st#network_change action ();

  end

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Switch ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let s = ((Obj.magic d):> User_level_switch.switch) in
     let title = (s_ "Modify switch")^" "^name in
     let label = s#get_label in
     let port_no = s#get_port_no in
     let port_no_min = st#network#port_no_lower_of (s :> User_level.node) in
     let show_vde_terminal = s#get_show_vde_terminal in
     let activate_fstp = s#get_activate_fstp in
     let rc_config = s#get_rc_config in
     Dialog_add_or_update.make
       ~title ~name ~label ~port_no ~port_no_min
       ~show_vde_terminal ~activate_fstp ~rc_config
       ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; port_no = port_no;
                   old_name = old_name;
                   show_vde_terminal = show_vde_terminal;
                   activate_fstp = activate_fstp;
                   rc_config = rc_config }
      =
      let d = (st#network#get_node_by_name old_name) in
      let s = ((Obj.magic d):> User_level_switch.switch) in
      let action () = s#update_switch_with ~name ~label ~port_no ~show_vde_terminal ~activate_fstp ~rc_config in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist = Properties.dynlist

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "switch"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_switch.switch) in
      let action () = h#destroy in
      st#network_change action ();

  end

  module Startup = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist    = Properties.dynlist
    let dialog     = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#startup

  end

  module Stop = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Switch ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Switch ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Switch ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club: *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_switch;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add switch")
 ?(name="")
 ?label
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?(show_vde_terminal=false)
 ?(activate_fstp=false)
 ?(rc_config=(false, Const.initial_content_for_rcfiles))
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.switch.dialog.png")
 () :'result option =
  let old_name = name in
  let (dialog_switch,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "Switch")
      ~name
      ~name_tooltip:(s_ "Switch name. This name must be unique in the virtual network. Suggested: S1, S2, ...")
      ?label
      ()
  in
  let (port_no, show_vde_terminal, activate_fstp, rc_config) =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:dialog_switch#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [(s_ "Ports number");
         (s_ "Show VDE terminal");
         (s_ "Activate FSTP");
         (s_ "Startup configuration");
         ]
    in
    let port_no =
      Gui_bricks.spin_byte
        ~packing:(form#add_with_tooltip (s_ "Switch ports number"))
        ~lower:port_no_min ~upper:port_no_max ~step_incr:2
        port_no
    in
    let show_vde_terminal =
      GButton.check_button
        ~active:show_vde_terminal
        ~packing:(form#add_with_tooltip (s_ "Check to access the switch through a terminal" ))
        ()
    in
    let activate_fstp =
      GButton.check_button
        ~active:activate_fstp
        ~packing:(form#add_with_tooltip (s_ "Check to activate the FSTP (Fast Spanning Tree Protocol)" ))
        ()
    in
    let rc_config =
       Gui_bricks.make_rc_config_widget
         ~filter_names:[`CONF; `RC; `ALL]
         ~parent:(dialog_switch :> GWindow.window_skel)
         ~packing:(form#add_with_tooltip (s_ "Check to activate a startup configuration" ))
         ~active:(fst rc_config)
         ~content:(snd rc_config)
         ~device_name:(old_name)
         ~language:("vde_switch") (* special syntax *)
         ()
    in
    (port_no, show_vde_terminal, activate_fstp, rc_config)
  in
  (* --- *)
  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
    let port_no = int_of_float port_no#value in
    let show_vde_terminal = show_vde_terminal#active in
    let rc_config = (rc_config#active, rc_config#content) in
    let activate_fstp = activate_fstp#active in
      { Data.name = name;
        Data.label = label;
        Data.port_no = port_no;
        Data.show_vde_terminal = show_vde_terminal;
        Data.activate_fstp = activate_fstp;
        Data.rc_config = rc_config;
        Data.old_name = old_name;
        }
  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel (dialog_switch) ~ok_callback ~help_callback ~get_widget_data ()

(*-----*)
  WHERE
(*-----*)

 let help_callback =
   let title = (s_ "ADD OR MODIFY A SWITCH") in
   let msg   = (s_ "\
In this dialog window you can define the name of an Ethernet switch \
and set parameters for it:\n\n\
- Label: a string appearing near the switch icon in the network graph; it may \
allow, for example, to know at a glance the Ethernet network realized by the device; \
this field is exclusively for graphic purposes, is not taken in consideration \
for the configuration.\n\n\
- Nb of Ports: the number of ports of the switch (default 4); this number must \
not be increased without a reason, because the number of processes needed for the \
device emulation is proportional to his ports number.")
   in Simple_dialogs.help title msg

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_switch (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("switch", attrs) ->
    	let name  = List.assoc "name" attrs in
	let port_no = int_of_string (List.assoc "port_no" attrs) in
        Log.printf2 "Importing switch \"%s\" with %d ports...\n" name port_no;
	let x = new User_level_switch.switch ~network ~name ~port_no () in
	x#from_tree ("switch", attrs) children;
        Log.printf1 "Switch \"%s\" successfully imported.\n" name;
        true

    (* backward compatibility *)
    | ("device", attrs) ->
	let name  = List.assoc "name" attrs in
	let port_no = try int_of_string (List.assoc "eth" attrs) with _ -> Const.port_no_default in
	let kind = List.assoc "kind" attrs in
	(match kind with
	| "switch" ->
            Log.printf2 "Importing switch \"%s\" with %d ports...\n" name port_no;
	    let x = new User_level_switch.switch ~network ~name ~port_no () in
	    x#from_tree ("device", attrs) children; (* Just for the label... *)
            Log.printf "This is an old project: we set the user port offset to 1...\n";
	    network#defects#change_port_user_offset ~device_name:name ~user_port_offset:1;
	    Log.printf1 "Switch \"%s\" successfully imported.\n" name;
	    true
	| _ -> false
	)
   | _ -> false
   )
  with _ -> false

end (* module Eval_forest_child *)


(*-----*)
  WHERE
(*-----*)


module User_level_switch = struct

class switch =

 fun ~network
     ~name
     ?label
     ~port_no
     ?(show_vde_terminal=false)
     ?(activate_fstp=false)
     ?(rc_config=(false,""))
     () ->
  object (self) inherit OoExtra.destroy_methods ()

  inherit
    User_level.node_with_ledgrid_and_defects
      ~network
      ~name ?label ~devkind:`Switch
      ~port_no
      ~port_no_min:Const.port_no_min
      ~port_no_max:Const.port_no_max
      ~user_port_offset:1 (* in order to have a perfect mapping with VDE *)
      ~port_prefix:"port"
      ()
    as self_as_node_with_ledgrid_and_defects

  method ledgrid_label = "Switch"
  method defects_device_type = "switch"
  method polarity = User_level.MDI_X
  method string_of_devkind = "switch"

  val mutable show_vde_terminal : bool = show_vde_terminal
  method get_show_vde_terminal = show_vde_terminal
  method set_show_vde_terminal x = show_vde_terminal <- x

  val mutable activate_fstp : bool = activate_fstp
  method get_activate_fstp  = activate_fstp
  method set_activate_fstp x = activate_fstp <- x

  val mutable rc_config : bool * string  = rc_config
  method get_rc_config = rc_config
  method set_rc_config x = rc_config <- x

  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   (imgDir^"ico.switch."^(self#string_of_simulated_device_state)^"."^iconsize^".png")

  method update_switch_with ~name ~label ~port_no
   ~show_vde_terminal ~activate_fstp ~rc_config
   =
   (* The following call ensure that the simulated device will be destroyed: *)
   self_as_node_with_ledgrid_and_defects#update_with ~name ~label ~port_no;
   self#set_show_vde_terminal (show_vde_terminal);
   self#set_activate_fstp (activate_fstp);
   self#set_rc_config (rc_config);

  (** Create the simulated device *)
  method private make_simulated_device =
    let hublet_no = self#get_port_no in
    let show_vde_terminal = self#get_show_vde_terminal in
    let fstp = Option.of_bool (self#get_activate_fstp) in
    let rcfile_content =
      match self#get_rc_config with
      | false, _ -> None
      | true, content -> Some content
    in
    let unexpected_death_callback = self#destroy_because_of_unexpected_death in
    ((new Simulation_level_switch.switch
       ~parent:self
       ~hublet_no          (* TODO: why not accessible from parent? *)
       ~show_vde_terminal  (* TODO: why not accessible from parent? *)
       ?fstp
       ?rcfile_content
       ~working_directory:(network#project_working_directory)
       ~unexpected_death_callback
       ()) :> User_level.node Simulation_level.device)

  method to_tree =
   Forest.tree_of_leaf ("switch", [
      ("name"     ,  self#get_name );
      ("label"    ,  self#get_label);
      ("port_no"  ,  (string_of_int self#get_port_no))  ;
      ("show_vde_terminal" , string_of_bool (self#get_show_vde_terminal));
      ("activate_fstp"     , string_of_bool (self#get_activate_fstp));
      ("rc_config"         , Marshal.to_string self#get_rc_config []);
      ])

  method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | ("port_no"  , x ) -> self#set_port_no (int_of_string x)
  | ("show_vde_terminal", x ) -> self#set_show_vde_terminal (bool_of_string x)
  | ("activate_fstp", x )     -> self#set_activate_fstp (bool_of_string x)
  | ("rc_config", x )         -> self#set_rc_config (Marshal.from_string x 0)
  | _ -> () (* Forward-comp. *)

end (* class switch *)

end (* module User_level *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_switch = struct

(* The question is "port/print" *)
let scan_vde_switch_answer_to_port_print (ch:Network.stream_channel) : int =
  let rec loop n =
    let answer = ch#input_line () in
    try (Scanf.sscanf answer "Port %d %s ACTIVE") (fun i _ -> ()); loop (n+1) with _ ->
    try (Scanf.sscanf answer ".") (); n with _ -> loop n
  in
  loop 0

let ask_vde_switch_for_current_active_ports ~socketfile () =
  let protocol (ch:Network.stream_channel) =
    ch#output_line "port/print";
    scan_vde_switch_answer_to_port_print ch
  in
  Network.stream_client ~target:(`unix socketfile) ~protocol ()

let wait_vde_switch_until_ports_will_be_allocated ~numports ~socketfile () =
  let rec protocol (ch:Network.stream_channel) =
    ch#output_line "port/print";
    let active_ports = scan_vde_switch_answer_to_port_print ch in
    if active_ports >= numports then active_ports else (Thread.delay 0.2; (protocol ch))
  in
  Network.stream_client ~target:(`unix socketfile) ~protocol ()

(*let send_commands_to_vde_switch ~socketfile ~commands () =
  Log.printf "Sending commands to a switch:\n---\n%s\n---\n" commands;
  let protocol (ch:Network.stream_channel) = ch#send commands in
  Network.stream_unix_client ~socketfile ~protocol ()*)

let get_lines_removing_comments (commands:string) : string list =
  let t = StringExtra.Text.of_string commands in
  let result = StringExtra.Text.grep (Str.regexp "^[^#]") t in
  result

(* Currently unused, but useful for testing: *)
let get_vde_switch_boolean_answer (ch:Network.stream_channel) : bool =
  let ignore2 _ _ = () in
  let rec loop () =
    Log.printf "Waiting for an answer...\n";
    let answer = ch#input_line () in
    Log.printf1 "Received answer `%s'\n" answer;
    try (Scanf.sscanf answer "vde$ 1000 Success" ()); true with _ ->
    try (Scanf.sscanf answer "vde$ %d %s" ignore2); false with _ ->
    loop ()
  in
  loop ()

(* Currently unused, but useful for testing: *)
let send_commands_to_vde_switch_and_get_answers ~socketfile ~commands ()
  : (exn, (string * bool) list) Either.t
  =
  let lines = get_lines_removing_comments commands in
  Log.printf1 "Sending commands to a switch:\n---\n%s\n---\n" commands;
  let protocol (ch:Network.stream_channel) =
    List.map
       (fun line ->
          Log.printf1 "Sending line: %s\n" line;
          ch#output_line line;
          let answer = get_vde_switch_boolean_answer ch in
          Log.printf1 "Received boolean answer: %b\n" (answer);
          (line, answer))
       lines
  in
  Network.stream_client ~target:(`unix socketfile) ~protocol ()

let rec repeat_until_exception f x =
 try ignore (f x); repeat_until_exception f x with _ -> ()

let send_commands_to_vde_switch_ignoring_answers ~socketfile ~commands () =
  let lines = get_lines_removing_comments commands in
  let protocol (ch:Network.stream_channel) =
    ignore (Thread.create (repeat_until_exception ch#input_line) ());
    List.iter
       (fun line ->
          Log.printf1 "Sending line: %s\n" line;
          ch#output_line line;
          Thread.delay 0.01;
          ())
       lines
  in
  Network.stream_client ~target:(`unix socketfile) ~protocol ()


(** A switch: just a [hub_or_switch] with [hub = false] *)
class ['parent] switch =
  fun ~(parent:'parent)
      ~hublet_no
      ?(last_user_visible_port_index:int option)
      ?(show_vde_terminal=false)
      ?fstp
      ?rcfile (* Unused: vde_switch doesn't interpret correctly commands provided in this way! *)
      ?rcfile_content
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit ['parent] Simulation_level.hub_or_switch
      ~parent
      ~hublet_no
      ?last_user_visible_port_index
      ~hub:false
      ~management_socket:()
      ?fstp
      ?rcfile
      ~working_directory
      ~unexpected_death_callback
      ()
      as super
  method device_type = "switch"

  method! spawn_internal_cables =
    match show_vde_terminal || (rcfile_content <> None) with
    | false -> super#spawn_internal_cables
    | true ->
        (* If the user want to configure VLANs etc, we must be sure that
           the port numbering will be the same for marionnet and vde_switch: *)
        let socketfile = Option.extract self#get_management_socket_name in
        let numports = ref (Either.extract (ask_vde_switch_for_current_active_ports ~socketfile ())) in
        let name = parent#get_name in
        Log.printf2 "The vde_switch %s has currently %d active ports.\n" name !numports;
        Log.printf1 "Spawning internal cables for switch %s...\n" name;
	List.iter (fun thunk -> thunk ())
	  (List.map (* Here map returns a list of thunks *)
	     begin fun internal_cable_process () ->
	       (* The protocol implemented here should ensure that vde_switch will not be solicited
	          before having accepted the previously asked connection. However, for safety we add
	          a little delay in order to give to vde_switch the time to allocate the previous port: *)
	       Thread.delay 0.1;
	       (* Now we launch the process that will ask vde_switch to obtain a new port: *)
	       internal_cable_process#spawn;
	       incr numports;
	       let answer =
	         Either.extract (wait_vde_switch_until_ports_will_be_allocated ~numports:(!numports) ~socketfile ())
	       in
	       (if answer <> !numports then
	          Log.printf3 "Unexpected vde_switch %s answer: %d instead of the expected value %d. Ignoring.\n" name answer !numports
	        );
	       Log.printf2 "Ok, the vde_switch %s has now %d allocated ports.\n" name !numports;
	       end
 	     self#get_internal_cable_processes);
 	(* Now send rc commands to the switch: *)
        match rcfile_content with
        | None -> ()
        | Some commands ->
            ignore
              (Thread.create
                 (send_commands_to_vde_switch_ignoring_answers ~socketfile ~commands)              ())


  initializer

  match show_vde_terminal with
  | false -> ()
  | true ->
    let name = parent#get_name in
    self#add_accessory_process
      (new Simulation_level.unixterm_process
        ~xterm_title:(name^" terminal")
        ~management_socket_name:(Option.extract self#get_management_socket_name)
 	~unexpected_death_callback:
 	   (fun i _ ->
 	      Death_monitor.stop_monitoring i;
 	      Log.printf2 "Terminal of switch %s closed (pid %d).\n" name i)
	())

end;;

end (* module Simulation_level_switch *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
