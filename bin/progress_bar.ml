(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2009, 2010, 2023  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010  Université Paris 13

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

(* Authors:
 * - Luca Saiu: initial version
 * - Jean-Vincent Loddo: make_progress_bar_dialog generalization, re-styling
     (and refactoring in 2023)
 *)

(* --- *)
module Log = Marionnet_log
module Capsule = Ocamlbricks.Channel
(* module Either = Ocamlbricks.Either *)
module Option = Ocamlbricks.Option
open Gettext

type kind = Pulse | Fill of (unit -> float)

(* --- *)
let update_interval = 200;; (* in milliseconds *)

(* --- *)
let destroy_progress_bar_dialog (window) =
  let () = GMain_actor.delegate window#destroy () in
  ()

(* Make a dialog with the following layout:

+----------------------------------------------+
|                  title                       |
+----------------------------------------------+
|  (info)     text_on_label                    |
|             text_on_sub_label                |
|             [  progress_bar           ]      |
+----------------------------------------------+
*)
let make_progress_bar_dialog
    ?(title=(s_ "A slow operation is in progress"))
    ?(text_on_label=(s_ "A slow operation is in progress"))
    ?(text_on_sub_label="")
    ?text_on_bar:(text_on_bar=(s_ "Please wait..."))
    ?(kind=Pulse)
    ?(modal=false)
    ?(position=(if modal then `CENTER else `NONE))
    (* Max life-time in seconds; this is a limit, if the window is not destroyed before: *)
    ?(max_lifetime=10.)
    ()
  =
  GMain_actor.apply_extract (fun () -> begin
    (* --- *)
    let window = GWindow.window ~title ~modal ~position ~border_width:10 ~resizable:false () in
    let () = if modal then ignore (window#event#connect#delete ~callback:(fun _ -> true)) in
    let () = window#set_icon (Some Icon.icon_pixbuf) in
    (* --- *)
    (* Table 2x3 *)
    let table = GPack.table ~columns:2 ~rows:3 ~row_spacings:10 ~col_spacings:10 ~packing:window#add () in
    let attach (x,y) = table#attach ~left:x ~top:y ~expand:`X ~fill:`BOTH in
    (* --- *)
    (* Icon *)
    let _icon = GMisc.image ~file:(Initialization.Path.images^"ico.info.orig.png") ~xalign:0. ~packing:(attach (1,1)) () in
    (* --- *)
    (* Label *)
    let label = (GMisc.label ~xalign:0. ~packing:(attach (2,1)) ()) in
    let () = (label#set_use_markup true); (label#set_label text_on_label) in
    (* --- *)
    (* Sub label *)
    let () = if text_on_sub_label <> "" then
      let sub_label = (GMisc.label ~xalign:0. ~packing:(attach (2,2)) ()) in
      ((sub_label#set_use_markup true); (sub_label#set_label text_on_sub_label))
    in
    (* --- *)
    (* Progress bar *)
    let progress_bar = GRange.progress_bar ~pulse_step:0.2 () ~packing:(attach (2,3)) in
    progress_bar#set_text text_on_bar;
    (* --- *)
    (* No more than 10 seconds (?max_lifetime) for any progress_bar: *)
    let action () = match kind with Pulse  -> progress_bar#pulse () | Fill f -> progress_bar#set_fraction (f ()) in
    let delay = max_lifetime /. 20. in (* max_lifetime=10. => delay=0.5 *)
    let () = Thread.create (fun () ->
      for _ = 1 to 20 do
        Thread.delay (delay);
        GMain_actor.delegate action ()
      done;
      Log.printf  "Progress_bar.make: created thread: delegating the GTK main thread for window#destroy (if needed)\n";
      GMain_actor.delegate window#destroy ()
      ) () |> ignore
    in
    (* --- *)
    let () = window#show () in
    (* --- *)
    window
    (* --- *)
  end) ()
;;

