(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2009, 2010  Université Paris 13

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

(* --- *)
module StackExtra = Ocamlbricks.StackExtra
(* --- *)
open Gettext

(** Layouts for component-related menus. See the file gui_machine.ml for an example of application. *)

(** Function which appends entries to a toolbar *)
module Toolbar = struct

  (* Note that ~label:"" is very important in the call of GMenu.image_menu_item. Actually, it is a workaround
      of something that resemble to a bug in lablgtk: if not present, another external function is internally
      called by this function and the result is a menu entry with an horizontal line in background... *)
(*  let append_image_menu_OLD_TO_BE_REMOVED (toolbar:GButton.toolbar) filename tooltip =
    let slot    = GButton.tool_item ~packing:toolbar#insert () in
    let menubar = GMenu.menu_bar ~border_width:0 ~width:0 ~height:56 (* 60 *) ~packing:(slot#add) () in
    let image   = GMisc.image ~xalign:0.5 ~yalign:0.5 ~xpad:0 ~ypad:0 ~file:(Initialization.Path.images^filename) () in
    let result  = GMenu.image_menu_item ~label:"" ~image ~packing:menubar#add () in
    let set_tooltip w text = (GData.tooltips ())#set_tip w ~text in
    result#image#misc#show ();
    set_tooltip slot#coerce tooltip;
    result*)

(* NEW version (v0, unused), lablgtk3 compatible: *)
let append_image_menu_v0 (toolbar:GButton.toolbar) filename tooltip =
  let slot    = GButton.tool_item ~packing:toolbar#insert () in
  let box     = GPack.hbox ~border_width:2 ~packing:(slot#add) ~show:true () in
  let image   = GMisc.image ~xalign:0.5 ~yalign:0.5 ~xpad:0 ~ypad:0 ~file:(Filename.concat Initialization.Path.images filename) ~packing:(box#pack) () in
  let menubar = GMenu.menu_bar ~border_width:0 ~width:0 ~height:56 (* 60 *) ~packing:(box#pack) () in
  let result  = GMenu.menu_item ~label:"+" ~packing:menubar#add () in
  let () = image#misc#show () in
  let () = GtkBase.Widget.Tooltip.set_text slot#as_widget tooltip in
  result

(* NEW version, lablgtk3 compatible: *)
let append_image_menu(*_v1*) (toolbar:GButton.toolbar) filename tooltip =
  let slot    = GButton.tool_item ~packing:toolbar#insert () in
  let box     = GPack.hbox ~border_width:2 ~packing:(slot#add) ~show:true () in
  let menubar = GMenu.menu_bar ~border_width:0 ~width:0 ~height:56 (* 60 *) ~packing:(box#pack) () in
  let result  : GMenu.menu_item = Menu_factory.Image_menu_item.make ~file:(Filename.concat Initialization.Path.images filename) ~text:" 🢒" () in
  let () = menubar#add (result) in
  let () = GtkBase.Widget.Tooltip.set_text slot#as_widget tooltip in
  result

end (* module Toolbar *)

module type Toolbar_entry =
 sig
  val imagefile : string
  val tooltip   : string
  val packing   : [ `toolbar of GButton.toolbar | `menu_parent of Menu_factory.menu_parent ]
 end

module type State = sig val st:State.globalState end

module Layout_for_network_component
 (State         : sig val st:State.globalState end)
 (Toolbar_entry : Toolbar_entry)
 (Add           : Menu_factory.Entry_callbacks)
 (Properties    : Menu_factory.Entry_with_children_callbacks)
 (Remove        : Menu_factory.Entry_with_children_callbacks)
 = struct

  let menu_parent =
    match Toolbar_entry.packing with
    | `toolbar toolbar ->
         let image_menu_item = Toolbar.append_image_menu (toolbar) (Toolbar_entry.imagefile) (Toolbar_entry.tooltip) in
         Menu_factory.Menuitem (image_menu_item :> GMenu.menu_item_skel)
    | `menu_parent p -> p

  module F = Menu_factory.Make (struct
    let parent = menu_parent
    let window = State.st#mainwin#window_MARIONNET
  end)

 module Add' = struct
   include Add
   let text  = (s_ "Add")
   let stock = `ADD
   end

 module Properties' = struct
   include Properties
   let text  = (s_ "Modify")
   let stock = `PROPERTIES
   end

 module Remove' = struct
   include Remove
   let text  = (s_ "Remove")
   let stock= `REMOVE
   end

 module Created_Add        = Menu_factory.Make_entry               (Add')        (F)
 module Created_Properties = Menu_factory.Make_entry_with_children (Properties') (F)
 module Created_Remove     = Menu_factory.Make_entry_with_children (Remove')     (F)

end


module Layout_for_network_node
 (State         : sig val st:State.globalState end)
 (Toolbar_entry : Toolbar_entry)
 (Add        : Menu_factory.Entry_callbacks)
 (Properties : Menu_factory.Entry_with_children_callbacks)
 (Remove     : Menu_factory.Entry_with_children_callbacks)
 (Startup    : Menu_factory.Entry_with_children_callbacks)
 (Stop       : Menu_factory.Entry_with_children_callbacks)
 (Suspend    : Menu_factory.Entry_with_children_callbacks)
 (Resume     : Menu_factory.Entry_with_children_callbacks)
 = struct

 module Startup' = struct
   include Startup
   let text  = (s_ "Start")
   let stock = `EXECUTE
   end

 module Stop' = struct
   include Stop
   let text  = (s_ "Stop")
   let stock = `MEDIA_STOP
   end

 module Suspend' = struct
   include Suspend
   let text  = (s_ "Suspend")
   let stock = `MEDIA_PAUSE
   end

 module Resume' = struct
   include Resume
   let text  = (s_ "Resume")
   let stock = `MEDIA_PLAY
   end

 module Created_entries_for_network_component = Layout_for_network_component (State) (Toolbar_entry) (Add) (Properties) (Remove)
 module F = Created_entries_for_network_component.F
 let () = F.add_separator ()
 module Created_Startup = Menu_factory.Make_entry_with_children (Startup') (F)
 module Created_Stop    = Menu_factory.Make_entry_with_children (Stop')    (F)
 let () = F.add_separator ()
 module Created_Suspend = Menu_factory.Make_entry_with_children (Suspend') (F)
 module Created_Resume  = Menu_factory.Make_entry_with_children (Resume')  (F)

end

module Layout_for_network_node_with_state
 (State             : sig val st:State.globalState end)
 (Toolbar_entry     : Toolbar_entry)
 (Add               : Menu_factory.Entry_callbacks)
 (Properties        : Menu_factory.Entry_with_children_callbacks)
 (Remove            : Menu_factory.Entry_with_children_callbacks)
 (Startup           : Menu_factory.Entry_with_children_callbacks)
 (Stop              : Menu_factory.Entry_with_children_callbacks)
 (Suspend           : Menu_factory.Entry_with_children_callbacks)
 (Resume            : Menu_factory.Entry_with_children_callbacks)
 (Ungracefully_stop : Menu_factory.Entry_with_children_callbacks)
 = struct

 module Ungracefully_stop' = struct
   include Ungracefully_stop
   let text  = (s_ "Power-off")
   let stock = `DISCONNECT
   end

 module Created_entries_for_network_node = Layout_for_network_node (State) (Toolbar_entry) (Add) (Properties) (Remove) (Startup) (Stop) (Suspend) (Resume)
 module F = Created_entries_for_network_node.F
 let () = F.add_separator ()
 module Created_Ungracefully_stop = Menu_factory.Make_entry_with_children (Ungracefully_stop') (F)

end


module Layout_for_network_edge
 (State             : sig val st:State.globalState end)
 (Toolbar_entry     : Toolbar_entry)
 (Add        : Menu_factory.Entry_callbacks)
 (Properties : Menu_factory.Entry_with_children_callbacks)
 (Remove     : Menu_factory.Entry_with_children_callbacks)
 (Disconnect : Menu_factory.Entry_with_children_callbacks)
 (Reconnect  : Menu_factory.Entry_with_children_callbacks)
 = struct

 module Disconnect' = struct
   include Disconnect
   let text  = (s_ "Disconnect")
   let stock = `DISCONNECT
   end

 module Reconnect' = struct
   include Reconnect
   let text  = (s_ "Re-connect")
   let stock = `CONNECT
   end

 module Created_entries_for_network_component = Layout_for_network_component (State) (Toolbar_entry) (Add) (Properties) (Remove)
 module F = Created_entries_for_network_component.F
 let () = F.add_separator ()
 module Created_Disconnect = Menu_factory.Make_entry_with_children (Disconnect') (F)
 module Created_Reconnect  = Menu_factory.Make_entry_with_children (Reconnect') (F)

 (* Cable sensitiveness *)
 module Created_Add = Created_entries_for_network_component.Created_Add
 let () = StackExtra.push (Created_Add.item#coerce) (State.st#sensitive_cable_menu_entries)

end

