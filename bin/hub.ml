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


(** "Hub" component implementation. *)

#load "where_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module OoExtra = Ocamlbricks.OoExtra
module Forest = Ocamlbricks.Forest
module Xforest = Ocamlbricks.Xforest
(* --- *)
open Gettext

(* Hub related constants: *)
(* TODO: make it configurable! *)
module Const = struct
 let port_no_default = 4
 let port_no_min = 4
 let port_no_max = 16
end

(* The type of data exchanged with the dialog: *)
module Data = struct
type t = {
  name        : string;
  label       : string;
  port_no     : int;
  old_name    : string;
  }

let to_string t = "<obj>" (* TODO? *)
end (* Data *)

module Make_menus (Params : sig
  val st      : State.globalState
  val packing : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end) = struct

  open Params

  module Toolbar_entry = struct
   let imagefile = "ico.hub.palette.png"
   let tooltip   = (s_ "Hub")
   let packing   = Params.packing
  end

  module Add = struct
    include Data

    let key = Some GdkKeysyms._H

    let ok_callback t = Gui_bricks.Ok_callback.check_name t.name t.old_name st#network#name_exists t

    let dialog () =
      let name = st#network#suggestedName "H" in
      Dialog_add_or_update.make ~title:(s_ "Add hub") ~name ~ok_callback ()

    let reaction { name = name; label = label; port_no = port_no; _ } =
      let action () = ignore (new User_level_hub.hub ~network:st#network ~name ~label ~port_no ()) in
      st#network_change action ();

  end

  module Properties = struct
    include Data
    let dynlist () = st#network#get_node_names_that_can_startup ~devkind:`Hub ()

    let dialog name () =
     let d = (st#network#get_node_by_name name) in
     let title = (s_ "Modify hub")^" "^name in
     let label = d#get_label in
     let port_no = d#get_port_no in
     let port_no_min = st#network#port_no_lower_of (d :> User_level.node) in
     Dialog_add_or_update.make ~title ~name ~label ~port_no ~port_no_min ~ok_callback:Add.ok_callback ()

    let reaction { name = name; label = label; port_no = port_no; old_name = old_name; } =
      let d = (st#network#get_node_by_name old_name) in
      let h = ((Obj.magic d):> User_level_hub.hub) in
      let action () = h#update_with ~name ~label ~port_no in
      st#network_change action ();

  end

  module Remove = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")

    let dynlist = Properties.dynlist

    let dialog name () =
      Gui_bricks.Dialog.yes_or_cancel_question
        ~title:(s_ "Remove")
        ~markup:(Printf.sprintf (f_ "Are you sure that you want to remove %s\nand all the cables connected to this %s?") name (s_ "hub"))
        ~context:name
        ()

    let reaction name =
      let d = (st#network#get_node_by_name name) in
      let h = ((Obj.magic d):> User_level_hub.hub) in
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
    let dynlist () = st#network#get_node_names_that_can_gracefully_shutdown ~devkind:`Hub ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#gracefully_shutdown

  end

  module Suspend = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_suspend ~devkind:`Hub ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#suspend

  end

  module Resume = struct
    type t = string (* just the name *)
    let to_string = (Printf.sprintf "name = %s\n")
    let dynlist () = st#network#get_node_names_that_can_resume ~devkind:`Hub ()
    let dialog = Menu_factory.no_dialog_but_simply_return_name
    let reaction name = (st#network#get_node_by_name name)#resume

  end

 module Create_entries =
  Gui_toolbar_COMPONENTS_layouts.Layout_for_network_node (Params) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)

 (* Subscribe this kind of component to the network club: *)
 st#network#subscribe_a_try_to_add_procedure Eval_forest_child.try_to_add_hub;

end

(*-----*)
  WHERE
(*-----*)

module Dialog_add_or_update = struct

(* This function may be useful for testing the widget creation without
   recompiling the whole project. *)
let make
 ?(title="Add hub")
 ?(name="")
 ?label
 ?(port_no=Const.port_no_default)
 ?(port_no_min=Const.port_no_min)
 ?(port_no_max=Const.port_no_max)
 ?(help_callback=help_callback) (* defined backward with "WHERE" *)
 ?(ok_callback=(fun data -> Some data))
 ?(dialog_image_file=Initialization.Path.images^"ico.hub.dialog.png")
 () :'result option =
  let old_name = name in
  let (w,_,name,label) =
    Gui_bricks.Dialog_add_or_update.make_window_image_name_and_label
      ~title
      ~image_file:dialog_image_file
      ~image_tooltip:(s_ "Hub")
      ~name
      ~name_tooltip:(s_ "Hub name. This name must be unique in the virtual network. Suggested: H1, H2, ... ")
      ?label
      ()
  in
  let port_no =
    let vbox = GPack.vbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:w#vbox#add () in
    let form =
      Gui_bricks.make_form_with_labels
        ~packing:vbox#add
        [(s_ "Ports number")]
    in
    let port_no =
      Gui_bricks.spin_byte
        ~packing:(form#add_with_tooltip (s_ "Hub ports number"))
        ~lower:port_no_min ~upper:port_no_max ~step_incr:2
        port_no
    in
    port_no
  in

  let get_widget_data () :'result =
    let name = name#text in
    let label = label#text in
    let port_no = int_of_float port_no#value in
      { Data.name = name;
        Data.label = label;
        Data.port_no = port_no;
        Data.old_name = old_name;
        }
  in
  (* The result of make is the result of the dialog loop (of type 'result option): *)
  Gui_bricks.Dialog_run.ok_or_cancel w ~ok_callback ~help_callback ~get_widget_data ()

(*-----*)
  WHERE
(*-----*)

 let help_callback =
   let title = (s_ "ADD OR MODIFY A HUB") in
   let msg   = (s_ "\
In this dialog window you can define the name of an Ethernet HUB \
and set parameters for it:\n\
- Label: a string appearing near the hub icon in the network graph; it may \
allow, for example, to know at a glance the Ethernet network realized by the device; \
this field is exclusively for graphic purposes, is not taken in consideration \
for the configuration.\n\
- Nb of Ports: the number of ports of the hub (default 4); this number must \
not be increased without a reason, because the number of processes needed for the \
device emulation is proportional to his ports number.")
   in Simple_dialogs.help title msg

end

(*-----*)
  WHERE
(*-----*)

module Eval_forest_child = struct

 let try_to_add_hub (network:User_level.network) ((root,children):Xforest.tree) =
  try
   (match root with
    | ("hub", attrs) ->
    	let name  = List.assoc "name" attrs in
	let port_no = int_of_string (List.assoc "port_no" attrs) in
        Log.printf2 "Importing hub \"%s\" with %d ports...\n" name port_no;
	let x = new User_level_hub.hub ~network ~name ~port_no () in
	x#from_tree ("hub", attrs) children;
        Log.printf1 "Hub \"%s\" successfully imported.\n" name;
        true

    (* backward compatibility *)
    | ("device", attrs) ->
	let name  = List.assoc "name" attrs in
	let port_no = try int_of_string (List.assoc "eth" attrs) with _ -> Const.port_no_default in
	let kind = List.assoc "kind" attrs in
	(match kind with
	| "hub" ->
            Log.printf2 "Importing hub \"%s\" with %d ports...\n" name port_no;
	    let x = new User_level_hub.hub ~network ~name ~port_no () in
	    x#from_tree ("hub", attrs) children; (* Just for the label... *)
            Log.printf "This is an old project: we set the user port offset to 1...\n";
	    network#defects#change_port_user_offset ~device_name:name ~user_port_offset:1;
	    Log.printf1 "Hub \"%s\" successfully imported.\n" name;
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


module User_level_hub = struct

class hub =

 fun ~network
     ~name
     ?label
     ~port_no
     () ->
  object (self) inherit OoExtra.destroy_methods ()

  inherit
    User_level.node_with_ledgrid_and_defects
      ~network
      ~name ?label ~devkind:`Hub
      ~port_no
      ~port_no_min:Const.port_no_min
      ~port_no_max:Const.port_no_max
      ~user_port_offset:1 (* in order to have a perfect mapping with VDE *)
      ~port_prefix:"port"
      ()
    (* as self_as_node_with_ledgrid_and_defects *)

  (* --- *)
  method ledgrid_label = "Hub"
  method defects_device_type = "hub"
  method polarity = User_level.MDI_X
  method string_of_devkind = "hub"

  (* --- *)
  method dotImg iconsize =
   let imgDir = Initialization.Path.images in
   (imgDir^"ico.hub."^(self#string_of_simulated_device_state)^"."^iconsize^".png")

  (** Create the simulated device *)
  method private make_simulated_device =
    let hublet_no = self#get_port_no in
    let unexpected_death_callback = self#destroy_because_of_unexpected_death in
    ((new Simulation_level_hub.hub
        ~parent:self
        ~hublet_no
        ~working_directory:(network#project_working_directory)
        ~unexpected_death_callback
        ()) :> User_level.node Simulation_level.device)

  (* --- *)
  method to_tree =
   Forest.tree_of_leaf ("hub", [
     ("name"     ,  self#get_name );
     ("label"    ,  self#get_label);
     ("port_no"  ,  (string_of_int self#get_port_no))  ;
     ])

  method! eval_forest_attribute = function
  | ("name"     , x ) -> self#set_name x
  | ("label"    , x ) -> self#set_label x
  | ("port_no"  , x ) -> self#set_port_no (int_of_string x)
  | _ -> () (* Forward-comp. *)

end (* class hub *)

end (* module User_level_hub *)

(*-----*)
  WHERE
(*-----*)

module Simulation_level_hub = struct

(** A hub: just a [hub_or_switch] with [hub = true] *)
class ['parent] hub =
  fun ~parent
      ~hublet_no
      ?(last_user_visible_port_index:int option)
      ~working_directory
      ~unexpected_death_callback
      () ->
object(self)
  inherit ['parent] Simulation_level.hub_or_switch
      ~parent
      ~hublet_no
      ?last_user_visible_port_index
      ~hub:true
      ~working_directory
      ~unexpected_death_callback
      ()
      (* as self_as_hub_or_switch *)

  method device_type = "hub"
end;;

end (* module Simulation_level_hub *)

(** Just for testing: *)
let test = Dialog_add_or_update.make
