(* This file is part of Marionnet
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

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module Cortex = Ocamlbricks.Cortex
module ListExtra = Ocamlbricks.ListExtra
module StrExtra = Ocamlbricks.StrExtra
module UnixExtra = Ocamlbricks.UnixExtra
module Egg = Ocamlbricks.Egg
module Widget = Ocamlbricks.Widget

open Gettext

type form = < (* object *)
  add              : GObj.widget -> unit;
  add_with_tooltip : ?just_for_label:unit -> string -> GObj.widget -> unit;
  add_section      : ?fg:string -> ?size:string -> ?no_line:unit -> string -> unit;
  set_sensitive    : label_text:string -> bool -> unit;
  coerce           : GObj.widget;
  table            : GPack.table;
  >

(** {b Example}:
\{\[
let tooltips = Gui_Bricks.make_tooltips_for_container window in
tooltips label#coerce "hello";
tooltips entry#coerce "salut";
\]\}
*)
(*(*(*let make_tooltips_for_container w =
  let result = (GData.tooltips ()) in
  let _ = w#connect#destroy ~callback:(fun _ -> result#destroy ()) in
  fun (widget:GObj.widget) text -> result#set_tip widget ~text*)*)*)
(* --- *)
let make_tooltips_for_container w =
  fun (widget:GObj.widget) text -> GtkBase.Widget.Tooltip.set_text (widget#as_widget) (text)

(** Make a classic rectangular input form with field labels at the left side
    and input widgets at the right side of each line.
    Labels are get from the input string list while input widgets are
    added later using the method [add]. {b Example}:
\{\[...
let form =
  Gui_Bricks.make_form_with_labels
    ~packing:vbox#add
    ["IPv4 address"; "DHCP service"]
in
let ipv4address  = GEdit.entry ~text:"10.0.2.1" ~packing:form#add () in
let dhcp_enabled = GButton.check_button ~packing:form#add () in
...\}\]
*)
let make_form_with_labels ?(section_no=0) ?(row_spacings=10) ?(col_spacings=10) ?packing string_list : form =
 let rows = (List.length string_list) + (section_no * 2) in
 let table = GPack.table ~row_spacings ~col_spacings ~rows ~columns:2 ~homogeneous:false ?packing () in
 let labels =
   Array.mapi
     (fun i label_text ->
        let label = GMisc.label ~xalign:0. ~markup:label_text () in
        label)
     (Array.of_list string_list)
 in
 let tooltip = make_tooltips_for_container table in
 object (self)
   method table = table
   method coerce = table#coerce
   val mutable field_index = 0
   val mutable row_index = 0
   val row_of_field : int array = (Array.make (Array.length labels) 0) (* Not currently used *)
   val widgets : GObj.widget array = Array.map (fun w -> w#coerce) labels (* array updated by methods #add and #add_with_tooltip *)
   (* --- *)
   method private register_mapping_then_increment_row_and_field_indexes =
     row_of_field.(field_index) <- row_index;
     row_index <- row_index+1;
     field_index <- field_index+1;

   method private aligned_widget widget =
     let box = GBin.alignment ~xalign:0. ~yalign:0.5 ~xscale:0.0 ~yscale:0.0 () in
     box#add widget#coerce;
     box

   method add =
     let top = row_index in (* top is in the closure *)
     let field = field_index in
     table#attach ~left:0 ~top (labels.(field))#coerce;
     self#register_mapping_then_increment_row_and_field_indexes;
     (* --- *)
     (function widget ->
       table#attach ~left:1 ~top (self#aligned_widget widget)#coerce;
       widgets.(field) <- widget#coerce;
       )

   method add_section ?(fg="#b4b4b4") (* was "lightgray" *) ?(size="large") ?no_line markup =
     let markup =
       Printf.sprintf "<span foreground='%s' size='%s'><b>%s</b></span>" fg size markup;
     in
     let label = GMisc.label ~xalign:0. ~markup () in
     let top = row_index+1 in
     row_index <- row_index+2; (* additional line for vertical spacing *)
     table#attach ~left:0 ~top label#coerce;
     (match no_line with
     | None ->
         (* No, lablgtk draws a strange big line, so in any case we do nothing: *)
         (* let sep = GMisc.separator `HORIZONTAL ~show:true () in
         table#attach ~left:1 ~top sep#coerce *)
         ()
     | _    -> ());

   method add_with_tooltip ?just_for_label text =
     let top = row_index in (* top is in the closure *)
     let field = field_index in
     table#attach ~left:0 ~top (Array.get labels field)#coerce;
     self#register_mapping_then_increment_row_and_field_indexes;
     (* --- *)
     (function widget ->
       table#attach ~left:1 ~top (self#aligned_widget widget)#coerce;
       (if just_for_label = None then tooltip widget text);
       tooltip ((labels.(field))#coerce) text;
       widgets.(field) <- widget#coerce;
       )

   method set_sensitive ~label_text b =
     try
       let i,_ = ListExtra.findi ((=)label_text) string_list in
       (labels.(i)#misc#set_sensitive b;
        widgets.(i)#misc#set_sensitive b)
     with Not_found -> ()
 end

(** Wrap the given widget with a label, using an hidden table which will be packaged
    in its container (if provided). The result is the input widget itself.
    {b Example}:
\{\[
let entry_with_label ?packing ?max_length ?entry_text ?labelpos label_text =
  let entry = GEdit.entry ?text:entry_text ?max_length () in
  Gui_Bricks.wrap_with_label ?packing ?labelpos label_text entry
\]\}
*)
let wrap_with_label ?tooltip ?packing ?(labelpos=`NORTH) label_text widget =
 let label = GMisc.label ~text:label_text () in
 let (rows, columns) =
   match labelpos with
   | `NORTH | `SOUTH -> 2,1
   | `EAST  | `WEST  -> 1,2
 in
 let table = GPack.table ~rows ~columns ~homogeneous:true ?packing () in
 let () = match labelpos with
   | `NORTH -> table#attach ~left:0 ~top:0 label#coerce;  table#attach ~left:0 ~top:1 widget#coerce
   | `SOUTH -> table#attach ~left:0 ~top:0 widget#coerce; table#attach ~left:0 ~top:1 label#coerce
   | `WEST  -> table#attach ~left:0 ~top:0 label#coerce;  table#attach ~left:1 ~top:0 widget#coerce
   | `EAST  -> table#attach ~left:0 ~top:0 widget#coerce; table#attach ~left:1 ~top:0 label#coerce
 in
 Option.iter ((make_tooltips_for_container table) table#coerce) tooltip;
 widget

(** A simple [GEdit.entry] equipped by a label specified as a string. *)
let entry_with_label ?tooltip ?packing ?max_length ?entry_text ?labelpos label_text =
  let entry = GEdit.entry ?text:entry_text ?max_length () in
  wrap_with_label ?tooltip ?packing ?labelpos label_text entry

(** Not in the interface.*)
let add_tooltip_label_and_labelpos_parameters ?tooltip ?label ?labelpos ?packing maker =
  match label with
  | None   -> maker ?tooltip ?packing ()
  | Some label_text ->
      let result = maker ?tooltip:None ?packing:None () in
      let _ = wrap_with_label ?tooltip ?packing ?labelpos label_text result in
      result

(** A spin for bytes, i.e. for values in the range [0..255].  *)
let spin_byte ?tooltip ?label ?labelpos ?(lower=0) ?(upper=255) ?(step_incr=1) ?packing value =
  let lower = float_of_int lower in
  let upper = float_of_int upper in
  let step_incr = float_of_int step_incr in
  let maker ?tooltip ?packing () =
    let sb = GEdit.spin_button ?packing (*~width:50*) (* 60 *) ~digits:0 ~numeric:true () in
    sb#adjustment#set_bounds ~lower ~upper ~step_incr ();
    sb#set_value (float_of_int value);
    Option.iter ((make_tooltips_for_container sb) sb#coerce) tooltip;
    sb
  in
  add_tooltip_label_and_labelpos_parameters ?tooltip ?label ?labelpos ?packing maker
;;

let byte_tooltips_default_array =
  Array.of_list [
    (s_ "First byte of the IPv4 address" );
    (s_ "Second byte of the IPv4 address" );
    (s_ "Third byte of the IPv4 address" );
    (s_ "Fourth byte of the IPv4 address" );
    (s_ "Netmask (CIDR notation)" );
    ]

(** Four spins for asking for an ipv4 address. *)
let spin_ipv4_address ?tooltip ?byte_tooltips ?label ?labelpos ?packing v1 v2 v3 v4 =
  let byte_tooltips = match byte_tooltips with
  | None   -> byte_tooltips_default_array
  | Some a -> a
  in
  let (tooltip_s1, tooltip_s2, tooltip_s3, tooltip_s4) =
   let a = byte_tooltips in
   (a.(0), a.(1), a.(2), a.(3))
  in
  let maker ?packing () =
    let table = GPack.table ~rows:1 ~columns:7 ~homogeneous:false ?packing () in
    let dot ~left = GMisc.label ~packing:(table#attach ~left ~top:0) ~width:15 ~markup:"<b>.</b>" () in
    let s1 = spin_byte ~tooltip:tooltip_s1 ~packing:(table#attach ~left:0 ~top:0) v1 in
    let _1 = dot ~left:1 in
    let s2 = spin_byte ~tooltip:tooltip_s2 ~packing:(table#attach ~left:2 ~top:0) v2 in
    let _2 = dot ~left:3 in
    let s3 = spin_byte ~tooltip:tooltip_s3 ~packing:(table#attach ~left:4 ~top:0) v3 in
    let _3 = dot ~left:5 in
    let s4 = spin_byte ~tooltip:tooltip_s4 ~packing:(table#attach ~left:6 ~top:0) v4 in
    (table,(s1,s2,s3,s4))
  in
  match label with
  | None   -> snd (maker ?packing ())
  | Some label_text ->
      let (table,(s1,s2,s3,s4)) = maker ?packing:None () in
      let _ = wrap_with_label ?tooltip ?packing ?labelpos label_text table in
      (s1,s2,s3,s4)

(** Four spins for asking for an ipv4 address, and a fifth for
    the netmask (in CIDR notation).  *)
let spin_ipv4_address_with_cidr_netmask
  ?tooltip ?byte_tooltips ?label ?labelpos ?packing v1 v2 v3 v4 v5
  =
  let byte_tooltips = match byte_tooltips with
  | None   -> byte_tooltips_default_array
  | Some a -> a
  in
  let (tooltip_s1, tooltip_s2, tooltip_s3, tooltip_s4, tooltip_s5) =
   let a = byte_tooltips in
   (a.(0), a.(1), a.(2), a.(3), a.(4))
  in
  let maker ?packing () =
    let table = GPack.table ~rows:1 ~columns:9 ~homogeneous:false ?packing () in
    let dot ~left = GMisc.label ~packing:(table#attach ~left ~top:0) ~width:15 ~markup:"<b>.</b>" () in
    let s1 = spin_byte ~tooltip:tooltip_s1 ~packing:(table#attach ~left:0 ~top:0) v1 in
    let _1 = dot ~left:1 in
    let s2 = spin_byte ~tooltip:tooltip_s2 ~packing:(table#attach ~left:2 ~top:0) v2 in
    let _2 = dot ~left:3 in
    let s3 = spin_byte ~tooltip:tooltip_s3 ~packing:(table#attach ~left:4 ~top:0) v3 in
    let _3 = dot ~left:5 in
    let s4 = spin_byte ~tooltip:tooltip_s4 ~packing:(table#attach ~left:6 ~top:0) v4 in
    let _slash = GMisc.label ~packing:(table#attach ~left:7 ~top:0) ~width:15 ~markup:"<b>/</b>" () in
    let s5 = spin_byte ~tooltip:tooltip_s5 ~packing:(table#attach ~left:8 ~top:0) v5 in
    (table,(s1,s2,s3,s4,s5))
  in
  match label with
  | None   -> snd (maker ?packing ())
  | Some label_text ->
      let (table,(s1,s2,s3,s4,s5)) = maker ?packing:None () in
      let _ = wrap_with_label ?tooltip ?packing ?labelpos label_text table in
      (s1,s2,s3,s4,s5)

(* An hbox containing a text entry activable with a check_button *)
let activable_entry
  ?packing
  ?(homogeneous=false)
  ?(active=false)
  ?text
  ?red_text_condition
  ()
  =
  let hbox = GPack.hbox ?packing ~homogeneous () in
  let check_button =
    GButton.check_button
      ~active
      ~packing:(hbox#add)
      ()
  in
  let entry =
    GEdit.entry ?text ~packing:(hbox#add) ()
  in
  (entry#misc#set_sensitive check_button#active);
  ignore (check_button#connect#toggled (fun () -> entry#misc#set_sensitive check_button#active));
  let () =
    match red_text_condition with
    | None -> ()
    | Some pred ->
	ignore (entry#connect#changed
	  (fun () ->
	      let states = [ `ACTIVE; `INSENSITIVE; `NORMAL; `PRELIGHT; `SELECTED ] in
	      match pred (entry#text) with
	      | false -> (entry#misc#modify_text (ListExtra.product2 states [`BLACK]);      check_button#misc#modify_bg (ListExtra.product2 states [`WHITE]))
	      | true  -> (entry#misc#modify_text (ListExtra.product2 states [`NAME "red"]); check_button#misc#modify_bg (ListExtra.product2 states [`NAME "red"]))
	      ))
  in
  object method active = check_button#active  method content = entry#text method hbox = hbox method entry = entry method check_button = check_button end


let add_help_button_if_necessary window = function
| None   -> (fun () -> ())
| Some f -> (window#add_button_stock `HELP `HELP; f)


module Ok_callback = struct

let check_name name old_name name_exists t =
  if not (StrExtra.Class.identifierp name)
  then begin
    Simple_dialogs.error
      (s_ "Ill-formed name" )
      ("Admissible characters are letters, digits and underscores." ) ();
    None   (* refused *)
  end else
  if (name <> old_name) && name_exists name
  then begin
    Simple_dialogs.error
      (s_ "Name conflict" )
      (Printf.sprintf(f_ "The name '%s' is already used in the virtual network. The names of virtual network elements must be unique." ) name)
      ();
    None   (* refused *)
  end else
  Some t (* accepted *)

end (* module Ok_callback *)


(** Wrappers for the method [run] of a dialog window. *)
module Dialog_run = struct

(** Wrapper for the method [run] of a dialog window.
    The function [get_widget_data] must extract the values from the dialog.
    The function [ok_callback] must check these values: if it consider that
    are incorrect, it returns [None] in order to continue the loop.
    Otherwise it builds the result [Some something] of the loop.
    If the [?help_callback] is not provided, the help button is not built.  *)
let ok_or_cancel
    (w:[ `CANCEL | `DELETE_EVENT | `HELP | `OK ] GWindow.dialog)
    ~(get_widget_data:unit -> 'a)
    ~(ok_callback:'a -> 'b option)
    ?help_callback () =
  begin
  let help_callback = add_help_button_if_necessary w help_callback in
  w#add_button_stock `CANCEL `CANCEL;
  w#add_button_stock `OK `OK;
  w#set_default_response `OK;
  w#set_response_sensitive `OK true;
  let result = ref None in
  let rec loop () =
    match w#run () with
    | `DELETE_EVENT | `CANCEL -> ()
    | `HELP -> (help_callback ()); loop ()
    | `OK ->
        (match ok_callback (get_widget_data ()) with
	| None   -> loop ()
	| Some d -> result := Some d
        )
  in
  (* The enter key has the same effect than pressing the OK button: *)
  let f_enter () = match ok_callback (get_widget_data ()) with
   | None   -> ()
   | Some d -> (result := Some d; ignore (w#event#send (GdkEvent.create `DELETE)))
  in
  let _ = w#event#connect#key_press ~callback:
    begin fun ev ->
      (if GdkEvent.Key.keyval ev = GdkKeysyms._Return then f_enter ());
      false
    end
  in
  loop ();
  w#destroy ();
  !result
  end


let set_key_meaning_to window key result value =
  let f_key () =
    (result := value; ignore (window#event#send (GdkEvent.create `DELETE)))
  in
  ignore (window#event#connect#key_press ~callback:
    begin fun ev ->
      (if GdkEvent.Key.keyval ev = key then f_key ());
      false
    end)


let yes_or_cancel
    (w:[ `CANCEL | `DELETE_EVENT | `HELP | `YES  ] GWindow.dialog)
    ?help_callback
    ~(context:'a)
    () : 'a option =
  begin
  let help_callback = add_help_button_if_necessary w help_callback in
  w#add_button_stock `CANCEL `CANCEL;
  w#add_button_stock `YES `YES;
  w#set_default_response `YES;
  w#set_response_sensitive `YES true;
  let result = ref None in
  let rec loop () =
    match w#run () with
    | `DELETE_EVENT | `CANCEL -> ()
    | `HELP -> (help_callback ()); loop ()
    | `YES -> result := Some context
  in
  (* The enter key has the same effect than pressing the YES button: *)
  set_key_meaning_to w GdkKeysyms._Return result (Some context);
  loop ();
  w#destroy ();
  !result
  end

(* Example: do you want to save the project before quitting? *)
let yes_no_or_cancel
    (w:[ `CANCEL | `DELETE_EVENT | `HELP | `NO | `YES  ] GWindow.dialog)
    ?help_callback
    ~(context:'a)
    () : ('a * bool) option =
  begin
  let help_callback = add_help_button_if_necessary w help_callback in
  w#add_button_stock `CANCEL `CANCEL;
  w#add_button_stock `NO `NO;
  w#add_button_stock `YES `YES;
  w#set_default_response `YES;
  w#set_response_sensitive `YES true;
  let result = ref None in
  let rec loop () =
    match w#run () with
    | `DELETE_EVENT | `CANCEL -> ()
    | `HELP -> (help_callback ()); loop ()
    | `YES -> result := Some (context,true)
    | `NO  -> result := Some (context,false)
  in
  (* The enter key has the same effect than pressing the YES button: *)
  set_key_meaning_to w GdkKeysyms._Return result (Some (context,true));
  loop ();
  w#destroy ();
  !result
  end

end (* module Dialog_run *)


let set_marionnet_icon window =
  let icon =
    let icon_file = Initialization.Path.images^"marionnet-launcher.png" in
    GdkPixbuf.from_file icon_file
  in
  (window#set_icon (Some icon))


module Dialog = struct

let make_a_window_for_a_question
 ?(title="Question")
 ?(image_filename=Initialization.Path.images^"ico.question-2.orig.png")
 ?markup
 ?text
 ()
 =
 let w = GWindow.dialog ~destroy_with_parent:true ~title ~modal:true ~resizable:false ~position:`CENTER () in
 set_marionnet_icon w;
 let hbox = GPack.hbox ~homogeneous:false ~border_width:20 ~spacing:10 ~packing:w#vbox#add () in
 let _image = GMisc.image ~file:image_filename ~xalign:0.5 ~packing:hbox#add () in
 let _label = GMisc.label ?markup ?text ~justify:`CENTER ~xalign:0.5 ~xpad:10 ~ypad:10 ~packing:hbox#add () in
 w


let yes_or_cancel_question ?title ?help_callback ?image_filename ?markup ?text
 ~(context:'a)
 () : 'a option
 =
  let w = make_a_window_for_a_question ?title ?image_filename ?markup ?text () in
  Dialog_run.yes_or_cancel w ?help_callback ~context ()


let yes_no_or_cancel_question ?title ?help_callback ?image_filename ?markup ?text
 ~(context:'a)
 () : ('a * bool) option
 =
  let w = make_a_window_for_a_question ?title ?image_filename ?markup ?text () in
  Dialog_run.yes_no_or_cancel w ?help_callback ~context ()

end (* module Dialog *)


type packing_function = GObj.widget -> unit

let make_combo_boxes_of_vm_installations
  ?on_distrib_change
  ?on_variant_change
  ?on_kernel_change
  ?distribution
  ?variant
  ?kernel
  ?updating
  ~packing
  (vm_installations : Disk.virtual_machine_installations)
  =
  (* Convert updating as boolean: *)
  let updating = (updating<>None) in
  (* Resolve the initial choice for distribution: *)
  let distribution = match distribution with
   | None   -> Option.extract vm_installations#filesystems#get_default_epithet
   | Some x -> x
   in
  (* Resolve the initial choice for variant: *)
  let variant = match variant with
   | None   -> "none"
   | Some x -> x
  in
  (* Resolve the initial choice for kernel: *)
  let kernel = match kernel with
   | None -> fst (List.hd (vm_installations#supported_kernels_of distribution))
   | Some x -> x
  in
  let (packing_distribution, packing_variant, packing_kernel) = packing in
  (* The user can't change filesystem and variant any more once the device has been created.
     TODO: release this constraint. *)
  let distribution_widget =
     let distribution_choices =
       match updating with
       | false -> (vm_installations#filesystems#get_epithet_list)
       | true  -> [distribution]
     in
     let variant_choices =
       fun epithet ->
         match updating with
         | false ->
            "none"::(vm_installations#variants_of epithet)#get_epithet_list
         | true -> [variant]
     in
     let kernel_choices =
       fun epithet -> List.map fst (vm_installations#supported_kernels_of epithet)
     in
     Widget.ComboTextTree.fromListWithTwoSlaves
       ~masterCallback:on_distrib_change
       ~masterPacking:(Some packing_distribution)
        distribution_choices
       ~slave0Callback:on_variant_change
       ~slave0Packing:(Some packing_variant)
        variant_choices
       ~slave1Callback:on_kernel_change
       ~slave1Packing:(Some packing_kernel)
        kernel_choices
    in
    let initial_variant_widget = distribution_widget#slave0
    and initial_kernel_widget = distribution_widget#slave1
    in
    (* Initialization: *)
    let () =
      (* Setting active values: *)
      distribution_widget#set_active_value distribution;
      initial_variant_widget#set_active_value variant;
      initial_kernel_widget#set_active_value kernel;
      (* Blocking changes updating: *)
      if updating then begin
	distribution_widget#box#misc#set_sensitive false;
	initial_variant_widget#box#misc#set_sensitive false;
      end else ()
    in
    (* The result: *)
    distribution_widget

module Dialog_add_or_update = struct

let make_window_image_name_and_label
  ~title
  ~image_file
  ~image_tooltip
  ~name
  ~name_tooltip
  ?label
  ?label_tooltip
  ()
  =
  let w = GWindow.dialog ~destroy_with_parent:true ~title ~modal:true ~position:`CENTER () in
  set_marionnet_icon w;
  let tooltips = make_tooltips_for_container w in
  let hbox = GPack.hbox ~homogeneous:true ~border_width:20 ~spacing:10 ~packing:w#vbox#add () in
  let image = GMisc.image ~file:image_file ~xalign:0.5 ~packing:hbox#add () in
  tooltips image#coerce image_tooltip;
  let vbox = GPack.vbox ~spacing:10 ~packing:hbox#add () in
  let name  = entry_with_label ~tooltip:name_tooltip ~packing:vbox#add ~entry_text:name  (s_ "Name") in
  let label =
    let tooltip = match label_tooltip with
    | None -> (s_ "Label to be written in the network sketch, next to the element icon." )
    | Some x -> x
    in
    entry_with_label ~tooltip ~packing:vbox#add ?entry_text:label (s_ "Label")
  in
  ignore (GMisc.separator `HORIZONTAL ~packing:w#vbox#add ());
  (w,image,name,label)

end (* module Dialog_add_or_update *)


module Reactive_widget = struct

  type abstract_combo_box_text = (item list) * (active_index option)
   and item = string
   and active_index = int (* 0..(n-1) *)
   and node = item
   and port = item

  let item_of_abstract_combo_box_text (xs, oi) : item option =
    Option.bind oi (fun i -> Option.apply_or_catch (List.nth xs) i)

  (** Slightly high-level combo_box_text class. The object is a couple widget-cortex where the cortex
      represents abstractly the state of the widget. This state is the list of items with the selected
      one, if any. When the cortex changes, the widget is destroyed and a new widget is regenerated.
      Conversely, when the widget changes, the cortex's selected value is updated. *)
  class combo_box_text
    ~(strings:string list)
    ?active
    ?width
    ?height
    ?packing
    () =
  let make_widget ?(active=0) (strings) =
    GEdit.combo_box_text ~strings ~use_markup:true ~active ?packing ?width ?height ()
  in
  let () = Log.printf1 "combo_box_text called with strings: %s\n" (String.concat " " strings) in
  object (self)
    (* --- *)
    val mutable cortex : (abstract_combo_box_text Cortex.t) = Cortex.return (strings, active)
    (* --- *)
    method cortex = cortex
    method activate_first = ignore (Cortex.move cortex (function ((_::_) as xs0, None) -> (xs0, Some 0) | v -> v))
    method get : string option = item_of_abstract_combo_box_text (Cortex.get cortex)
    (* --- *)
    val mutable widget = make_widget ?active (strings)
    method private widget_get : string option = GEdit.text_combo_get_active widget
    method private widget_set (active : int option) : unit = Option.iter ((fst widget)#set_active) active
    method private widget_remake (strings, active) =
      begin
        (fst widget)#destroy ();
        widget <- make_widget ?active strings;
        self#set_widget_to_cortex_connection;
      end
    (* --- *)
    (* widget -> cortex (to call for all created widgets) *)
    method private set_widget_to_cortex_connection =
      let change_state (xs0,_) = (* current state *)
        let a1 = Option.bind (self#widget_get) (fun x -> ListExtra.indexOf x xs0) in
        (xs0, a1)
      in
      let _ = (fst widget)#connect#changed (fun _ -> ignore (Cortex.move cortex change_state)) in
      ()
    (* --- *)
    (* cortex -> widget *)
    method private set_cortex_to_widget_connection =
      let on_commit (xs0,a0) (xs1,a1) = (* previous and proposed states *)
        if xs0 = xs1 then (self#widget_set a1) else (self#widget_remake (xs1,a1))
      in
      let _ = Cortex.on_commit_append (cortex) (on_commit) in
      ()
    (* --- *)
    method destroy () =
      let () = (fst widget)#destroy () in
      let () = Cortex.defuse cortex in
      ()
    (* --- *)
    initializer
       let () = self#set_cortex_to_widget_connection in
       let () = self#set_widget_to_cortex_connection in
       (* --- *)
       (* Add a resistance to the cortex: *)
       let resistance (xs0,a0) (xs1,a1) = (* previous and proposed states *)
         let () = Log.printf4 "combo_box_text RESISTANCE: previous: %s [%d]  proposed: %s [%d]\n"
           (String.concat "," xs0) (Option.extract_or a0 (-1)) (String.concat "," xs1) (Option.extract_or a1 (-1))
         in
         (* If the proposed state has no selected item, we activate the previously selected item, if it exists in the new list: *)
         let (xs1, a1) =
           match (xs0,a0), (xs1,a1) with
           | ((_::_), Some i0), ((_::_), None) ->
               let previously_active_item = (List.nth xs0 i0) in
               let a1' = ListExtra.indexOf (previously_active_item) (xs1) in
               (xs1, a1')
           | (_,_) -> (xs1, a1)
         in
         (xs1, a1) (* result of resistance! *)
       in
       let _ = Cortex.on_proposal_append (self#cortex) (resistance) in
       ()

  end (* class combo_box_text *)

  (* Domain power (four times): *)
  type 'a power4 = 'a * 'a * 'a * 'a

  let endpoints_partition_from_names
   ?(allow_loopback=true)              (* allow the two endpoints (n0 and n1) to be the same node *)
   (xys : (string * string) list)      (* The (node, port) list to partition *)
   (* Current constraints: *)
   (n0 : string option)                (* first  node name, if selected *)
   (p0 : string option)                (* first  port name, if selected *)
   (n1 : string option)                (* second node name, if selected *)
   (p1 : string option)                (* second port name, if selected *)
   (* Solution: *)
   : (abstract_combo_box_text) power4  (* the expected states (items and selected) of the four widgets *)
   =
   let nodes_of xys = ListExtra.uniq (List.map fst xys) in
   (* If there is a single node, we are forced to accept a loopback connection: *)
   let allow_loopback = allow_loopback || (List.length (nodes_of xys) <= 1) in
   let (>>=) = Option.bind in
   let index_of_optional_item (x : string option) xs =
     x >>= (fun x -> (Option.map fst (ListExtra.searchi ((=)x) xs)))
   in
   let substract ~node ~port xys =
     match (allow_loopback, node, port) with
     | (false, Some n0, _)       -> List.filter (fun (n,p)->n<>n0) xys
     | (true,  Some n0, Some p0) -> List.filter ((<>)(n0,p0)) xys
     | _                         -> xys
   in
   let ports_of x nps =
     ListExtra.filter_map (fun (n,p)-> if n=x then Some p else None) nps
   in
   (* --- *)
   let extract_or_take_from_list (node) (port) (nps) : string * string =
     match node, port with
     | None, _                                -> List.hd nps
     | Some n, Some p when List.mem (n,p) nps -> (n, p)
     | Some n, _                              -> (n, List.assoc n nps)
   in
   (* --- *)
   let xys0 = substract ~node:n1 ~port:p1 xys in
   let xs0 = nodes_of xys0 in
   (* --- *)
   let (n0, p0) : string * string = extract_or_take_from_list n0 p0 xys0 in
   let ys0 = ports_of (n0) xys0 in
   let xs0_active = index_of_optional_item (Some n0) xs0 in
   let ys0_active = index_of_optional_item (Some p0) ys0 in
   (* --- *)
   let xys1 = substract ~node:(Some n0) ~port:(Some p0) xys in
   let xs1  = nodes_of xys1 in
   let (n1, p1) : string * string = extract_or_take_from_list n1 p1 xys1 in
   let ys1 = ports_of (n1) xys1 in
   let xs1_active = index_of_optional_item (Some n1) xs1 in
   let ys1_active = index_of_optional_item (Some p1) ys1 in
   (* --- *)
   let () = Log.printf4 "group RESISTANCE: finishing we have (%s,%s) (%s,%s)\n" n0 p0 n1 p1 in
   let w1 = (xs0, xs0_active) in
   let w2 = (ys0, ys0_active) in
   let w3 = (xs1, xs1_active) in
   let w4 = (ys1, ys1_active) in
   (w1,w2,w3,w4)
   ;;

  (* Version suitable as resistance for the cortex group: *)
  let endpoints_partition_law ?allow_loopback (xys)
    : (abstract_combo_box_text) power4 -> (abstract_combo_box_text) power4 -> (abstract_combo_box_text) power4
    =
    fun (_,_,_,_) (c1,c2,c3,c4) -> (* previous and proposed states *)
      let n0 : string option = item_of_abstract_combo_box_text c1 in (* first  node name, if selected *)
      let p0 : string option = item_of_abstract_combo_box_text c2 in (* first  port name, if selected *)
      let n1 : string option = item_of_abstract_combo_box_text c3 in (* second node name, if selected *)
      let p1 : string option = item_of_abstract_combo_box_text c4 in (* second port name, if selected *)
      (* --- *)
      endpoints_partition_from_names ?allow_loopback xys n0 p0 n1 p1

  (* Version suitable to guess the initial division of choices (items) of the four widgets: *)
  let guess_humanly_speaking_enpoints ?n0 ?p0 ?n1 ?p1 xys =
    let ((xs0,_),(ys0,_),(xs1,_),(ys1,_)) = endpoints_partition_from_names ~allow_loopback:false xys n0 p0 n1 p1 in
    let x0 = Option.apply_or_catch List.hd xs0 in
    let y0 = Option.apply_or_catch List.hd ys0 in
    let x1 = Option.apply_or_catch List.hd xs1 in
    let y1 = Option.apply_or_catch List.hd ys1 in
    ((x0,y0),(x1,y1))


  class cable_input_widget
   ?n0 ?p0 ?n1 ?p1
   ?width
   ?height
   ?packing_n0 ?packing_p0 ?packing_n1 ?packing_p1
   ~free_node_port_list
   ()
   =
   let () = Log.printf1 "new cable_input_widget() called with: %s\n"
     (String.concat " " (List.map (fun (x,y) -> Printf.sprintf "%s.%s" x y) free_node_port_list))
   in
   let (w1,w2,w3,w4) = endpoints_partition_from_names (free_node_port_list) n0 p0 n1 p1 in
   let (xs0, xs0_active) = w1 in
   let (ys0, ys0_active) = w2 in
   let (xs1, xs1_active) = w3 in
   let (ys1, ys1_active) = w4 in
   (* --- *)
   let n0_combo_box_text =
     let packing = packing_n0 in
     new combo_box_text ~strings:xs0 ?active:xs0_active ?width ?height ?packing ()
   in
   let p0_combo_box_text =
     let packing = packing_p0 in
     new combo_box_text ~strings:ys0 ?active:ys0_active ?width ?height ?packing ()
   in
   let n1_combo_box_text =
     let packing = packing_n1 in
     new combo_box_text ~strings:xs1 ?active:xs1_active ?width ?height ?packing ()
   in
   let p1_combo_box_text =
     let packing = packing_p1 in
     new combo_box_text ~strings:ys1 ?active:ys1_active ?width ?height ?packing ()
   in
   let cortex_group =
     Cortex.group_quadruple
       ~on_proposal:(endpoints_partition_law ~allow_loopback:true (free_node_port_list))
       (n0_combo_box_text#cortex) (p0_combo_box_text#cortex)
       (n1_combo_box_text#cortex) (p1_combo_box_text#cortex)
   in
   object (self)

     method get_cortex_group = cortex_group
     method get_combo_boxes  = (n0_combo_box_text, p0_combo_box_text, n1_combo_box_text, p1_combo_box_text)

     method get_widget_data =
       ((n0_combo_box_text#get, p0_combo_box_text#get), (n1_combo_box_text#get, p1_combo_box_text#get))

     method destroy =
       let () =
         List.iter
           (fun w->w#destroy ())
           [n0_combo_box_text; p0_combo_box_text; n1_combo_box_text; p1_combo_box_text]
       in
       let () = Cortex.defuse cortex_group in
       ()

    initializer
       (* Very important to provoke the cortex_group's stabilization: *)
       n0_combo_box_text#activate_first;
       p0_combo_box_text#activate_first;
       n1_combo_box_text#activate_first;
       p1_combo_box_text#activate_first;

   end

end (* Reactive_widget *)

(* --- *)
let make_image_with_either_stock_or_file (*?window*) ?stock_size ?stock ?file () =
  let make_with_file file =
    (* Complete the filename if necessary: *)
    let file = if (Filename.is_implicit file) then Filename.concat (Initialization.Path.images) file else file in
    (* let pixmap = GDraw.pixmap_from_xpm ?window ~file () in
    let image  = GMisc.pixmap pixmap () in
    let () = if window <> None then Log.printf "make_image_with_either_stock_or_file: WARNING: actual ~window ignored\n" in *)
    let pixbuf : GdkPixbuf.pixbuf = GdkPixbuf.from_file (file) in
    let image  = GMisc.image ~pixbuf () in
    image
  in
  let make_with_stock stock =
    let icon_size = stock_size in
    GMisc.image ?icon_size ~stock ()
  in
  match stock,file with
  | None, Some file  -> make_with_file file
  | Some stock, None -> make_with_stock stock
  | _,_ -> failwith "Gui_Bricks.button_image: either ?stock or ?file is required"

(* The label and image positions are relative. Gtk speaks about the image position with
   respect to the label. So, if we want indeed to speak about the label position with
   respect to the image, we have to invert the value: *)
let opposite_position = function
 `BOTTOM -> `TOP | `LEFT -> `RIGHT | `RIGHT -> `LEFT | `TOP -> `BOTTOM

let button_image (*?window*) ?callback ?label ?label_position ?tooltip ~packing ?stock ?stock_size ?file () =
  let image = make_image_with_either_stock_or_file (*?window*) ?stock_size ?stock ?file () in
  let button = GButton.button ~packing () in
  let () = button#set_image image#coerce in
  let () = match callback with
  | None -> ()
  | Some callback -> ignore (button#connect#clicked ~callback)
  in
  (*let set_tooltip text = (GData.tooltips ())#set_tip button#coerce ~text in*)
  let set_tooltip text = GtkBase.Widget.Tooltip.set_text button#as_widget text in
  let () =
    Option.iter (button#set_label) label;
    Option.iter (fun p -> button#set_image_position (opposite_position p)) label_position;
    Option.iter set_tooltip tooltip
  in
  button

(** The ~renewer parameter allows us to generate dynamic menus
    (see the function `make_check_items_renewer_v1' below) *)
let button_image_popuping_a_menu
  (*?window*)
  ?renewer
  ?label ?label_position ?tooltip
  ~packing ?stock ?stock_size ?file () : (GMenu.menu * GButton.button * GPack.box)
  =
  let hbox = GPack.vbox ~homogeneous:false ~packing () in
  let button =
    button_image
      (*?window*) ?label ?label_position ?tooltip
      ~packing:(hbox#add)
      ?stock ?stock_size ?file ()
  in
  let menubar = GMenu.menu_bar ~packing:(hbox#add) () in
  let () = menubar#misc#hide () in
  let factory = new GMenu.factory menubar in
  let menu = factory#add_submenu "" in
  let _connect_clicked =
    let callback () =
      menu#popup ~button:0 ~time:(GtkMain.Main.get_current_event_time ())
    in
    (* Call before the renewer if provided: *)
    let callback =
      match renewer with
      | None -> callback
      | Some renewer -> (fun () -> (renewer menu); callback ())
    in
    button#connect#clicked ~callback
  in
  (menu, button, hbox)


let make_check_items_renewer_v1
 ~get_label_active_callback_list (* unit -> (string * bool * (bool -> unit)) list *)
 ()
 =
 fun (menu:GMenu.menu) ->
 begin
  let () = List.iter (menu#remove) (menu#children) in
  let label_active_callback_list = get_label_active_callback_list () in
  let () =
    List.iter
      (fun (label, active, callback) ->
         let item = GMenu.check_menu_item ~active ~label ~packing:(menu#append) () in
         let _ =
           item#connect#toggled
             ~callback:(fun () -> callback item#active)
         in ())
      label_active_callback_list
  in
  ()
 end


let make_check_items_renewer_v2
 ~get_label_active_list (* unit -> (string * bool) list *)
 ~callback (* string -> bool -> unit *)
 ()
 =
 let get_label_active_callback_list () =
   List.map
     (fun (label, active) -> (label, active, (fun b -> callback label b)))
     (get_label_active_list ())
 in
 make_check_items_renewer_v1 ~get_label_active_callback_list ()

(* Example of usage:
 make_rc_config_widget
   ~packing:(form#add_with_tooltip (s_ "Check to activate a startup configuration" ))
   ~active:(fst rc_config)
   ~content:(snd rc_config)
   ~device_name:(old_name)
   ~language:("vde_switch")
   ()
*)
let make_rc_config_widget ?height ?width ?(filter_names=[`CONF; `RC; `BASH; `SCRIPT; `TXT; `ALL]) ~parent ~packing ~active ~content ~device_name ~language () =
  (* let set_tooltip widget text = (GData.tooltips ())#set_tip widget#coerce ~text in *)
  let set_tooltip widget text = GtkBase.Widget.Tooltip.set_text widget#as_widget text in
  let hbox = GPack.hbox ~packing ~homogeneous:false(*true*) () in
  (* --- *)
  let check_button = GButton.check_button ~active ~packing:(hbox#add) () in
  (* --- *)
  let edit_button = GButton.button ~stock:`EDIT ~packing:hbox#add () in
  let () = set_tooltip (edit_button) (s_ "Edit the configuration file") in
  (* --- *)
  let open_button : GButton.button = button_image
    ~label:(s_ "Import" )
    ~tooltip:(s_ "Import a configuration file")
    ~packing:hbox#add
    ~stock:`ADD
    ~stock_size:`SMALL_TOOLBAR  (* [ `BUTTON | `DIALOG | `DND | `INVALID | `LARGE_TOOLBAR | `MENU | `SMALL_TOOLBAR ] *)
    ()
  in
  (* Shortcuts: *)
  let buttons = [check_button#coerce; edit_button#coerce; open_button#coerce] in
  let buttons_now_insensitive () = List.iter (fun b -> b#misc#set_sensitive false) buttons in
  let buttons_now_sensitive   () = List.iter (fun b -> b#misc#set_sensitive true)  buttons in
  (* --- *)
  let content = ref (content) in
  let make_editing_window () =
    let result = Egg.create () in
    let () =
      Gui_source_editing.window
        ?height ?width
        ~title:(Printf.sprintf (f_ "%s configuration file") device_name)
        ~language:(`id language)
        ~modal:()
        ~content:(!content)
        ~result
        ~create_as_dialog:(parent)
        ~draw_spaces:[]
        ~position:`MOUSE
        ()
    in
    ignore (Thread.create (fun () -> buttons_now_insensitive (); content := Option.extract_or (Egg.wait result) !content; buttons_now_sensitive ()) ());
  in
  ignore (edit_button#connect#clicked (make_editing_window));
  (edit_button#misc#set_sensitive check_button#active);
  ignore (check_button#connect#toggled (fun () -> edit_button#misc#set_sensitive check_button#active));
  (* --- *)
  let make_import_filename_dialog () =
    let () = buttons_now_insensitive () in
    let result =
      Talking.EDialog.ask_for_existing_importable_text_filename
        ~parent (* <= relevant to close and destroy this dialog if the user close the parent dialog;
                      NOTE: the behaviour is not the expected (but is not disturbing) probably because the window is modal. *)
        ~title:(Printf.sprintf (f_ "Import a configuration file for %s") device_name)
        (* ~title:(s_ "Import a configuration file" ) *)
        ~filter_names
        (* ~help:(Some Msg.help_nom_pour_le_projet)  *)
        ()
    in
    let () = buttons_now_sensitive () in
    Option.iter (fun env -> let filename = (env#get "filename") in content := UnixExtra.cat filename) result
  in
  ignore (open_button#connect#clicked (make_import_filename_dialog));
  (open_button#misc#set_sensitive check_button#active);
  ignore (check_button#connect#toggled (fun () -> open_button#misc#set_sensitive check_button#active));
  (* --- *)
  object (self)
    val mutable meaningfull : bool = true

    method active = meaningfull && check_button#active
    method content = !content

    method set_sensitive b =
      let () = Log.printf1 "rc_config_widget#set_sensitive called with %b\n" (b) in
      (hbox#misc#set_sensitive b);
      (meaningfull <- b)

  end

(* Example: quagga-terminal + {zebra, osp, ..} *)
let make_check_button_with_related_alternatives ~packing ~active ?(active_alternative=0) ?use_markup ~(alternatives:string list) () =
  let hbox = GPack.hbox ~packing ~homogeneous:false(*true*) () in
  let check_button = GButton.check_button ~active ~packing:(hbox#add) () in
  (* --- *)
  let (combo, (_, column)) =
    GEdit.combo_box_text ~packing:(hbox#add) ~strings:(alternatives) ?use_markup ()
  in
  let () = combo#set_active (active_alternative) in
  let () = combo#misc#set_sensitive (check_button#active) in
  ignore (check_button#connect#toggled (fun () -> combo#misc#set_sensitive check_button#active));
  (* --- *)
  object (self)
    val mutable meaningfull : bool = true

    method active = meaningfull && check_button#active
    method selected_alternative =
      Option.map (fun row -> combo#model#get ~row ~column) combo#active_iter

    method set_sensitive b =
      let () = Log.printf1 "make_check_button_with_related_alternatives#set_sensitive called with %b\n" (b) in
      (hbox#misc#set_sensitive b);
      (meaningfull <- b)
  end

(* --- *)
let make_notebook_of_assoc_list (*?homogeneous_tabs*) ~packing (tws: (string * GObj.widget) list) =
  let notebook = GPack.notebook (*?homogeneous_tabs*) ~packing () in
  let () =
    List.iter
      (fun (text, widget) ->
         let tab_label = (GMisc.label ~text ())#coerce in
         let _ = notebook#append_page ~tab_label widget in
         ())
      tws
  in
  notebook

let make_notebook_of_assoc_array_with_check_buttons
  ?(tooltip=(s_ "Check to activate"))
  (*?homogeneous_tabs*)
  ~packing
  (tbws: (string * bool * GObj.widget) array)
  =
  (* let set_tooltip widget text = (GData.tooltips ())#set_tip widget#coerce ~text in *)
  let set_tooltip widget text = GtkBase.Widget.Tooltip.set_text widget#as_widget text in
  (* --- *)
  let notebook = GPack.notebook (*?homogeneous_tabs*) ~packing () in
  Array.map
    (fun (text, active, widget) ->
        let hbox = GPack.hbox ~homogeneous:false(*true*) () in
        let _label = GMisc.label ~text ~packing:(hbox#add) () in
        let activate = GButton.check_button ~active ~packing:(hbox#add) () in
        let _ = activate#connect#toggled (fun () -> widget#misc#set_sensitive activate#active) in
        let () = widget#misc#set_sensitive activate#active in
        let () = set_tooltip hbox (tooltip) in
        let _ = notebook#append_page ~tab_label:(hbox#coerce) widget in
        activate)
    tbws


(* ---
Replace:
  let packing = toolbar#add in ...
with:
  let packing = Gui_bricks.make_toolbar_packing_function (toolbar) in ...
*)
let make_toolbar_packing_function ?homogeneous ?expand ?show (toolbar : GButton.toolbar) =
  let packing = function (widget: GObj.widget) ->
    (* val tool_item : ?homogeneous:bool -> ?expand:bool -> ?packing:(tool_item_o -> unit) -> ?show:bool -> unit -> tool_item *)
    let item = GButton.tool_item ?homogeneous ?expand ?show () in
    let () = item#add (widget) in
    (* method insert : ?pos:int (* -1 => append *) -> tool_item_o -> unit *)
    toolbar#insert (item)
  in
  packing

(* --- *)
let test () = Dialog.yes_or_cancel_question ~markup:"test <b>bold</b>" ~context:'a' ()
