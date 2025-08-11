(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
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
 * - Jean-Vincent Loddo: Unix.system calls replaced by UnixExtra's functions
     calls, and some other minor changes
 *)

(* --- *)
module Log = Marionnet_log
module Option = Ocamlbricks.Option
module UnixExtra = Ocamlbricks.UnixExtra
module StringExtra = Ocamlbricks.StringExtra
module FilenameExtra = Ocamlbricks.FilenameExtra
module Stateful_modules = Ocamlbricks.Stateful_modules
(* --- *)

open Gettext
module Row_item = Treeview.Row_item

(* --- *)
(* Ex: Some "Jean-Vincent Loddo" *)
let get_full_user_name () : string option =
  let user = Sys.getenv "USER" in
  let cmd = Printf.sprintf "getent passwd %s | cut -d: -f 5 | cut -d, -f 1" user in
  match UnixExtra.run cmd with
  | (full_name, Unix.WEXITED 0) -> Some (StringExtra.chop full_name)
  | _ -> None
(* --- *)

class t =
fun ~packing
    ~method_directory
    ~method_filename
    ~after_user_edit_callback
    () ->
object(self)
  inherit
    Treeview.t
      ~packing
      ~method_directory
      ~method_filename
      ~hide_reserved_fields:true
      ()
  (* as super *)

  val icon_header = "Icon"
  method get_row_icon = self#get_Icon_field (icon_header)
  method set_row_icon = self#set_Icon_field (icon_header)

  val title_header = "Title"
  method get_row_title = self#get_String_field (title_header)
  method set_row_title = self#set_String_field (title_header)

  val author_header = "Author"
  method get_row_author = self#get_String_field (author_header)
  method set_row_author = self#set_String_field (author_header)

  val type_header = "Type"
  method get_row_type = self#get_String_field (type_header)
  method set_row_type = self#set_String_field (type_header)

  val comment_header = "Comment"
  method get_row_comment = self#get_String_field (comment_header)
  method set_row_comment = self#set_String_field (comment_header)

  val filename_header = "FileName"
  method get_row_filename = self#get_String_field (filename_header)
  method set_row_filename = self#set_String_field (filename_header)

  val format_header = "Format"
  method get_row_format = self#get_String_field (format_header)
  method set_row_format = self#set_String_field (format_header)

  (** Display the document at the given row, in an asynchronous process: *)
  method private display row_id =
    let frmt = self#get_row_format (row_id) in
    let reader = self#format_to_reader frmt in
    let pathname = Filename.concat (self#directory) (self#get_row_filename row_id) in
    let command_line =
      Printf.sprintf "%s '%s'&" reader pathname in
    (* Here ~force:true would be useless, because of '&' (the shell well exit in any case). *)
    Log.system_or_ignore command_line

  val error_message =
    (s_ "You should select an existing document in PDF, Postscript, DVI, HTML or text format.")

  (** Ask the user to choose a file, and return its pathname. Fail if the user doesn't
      choose a file or cancels: *)
  method (* private *) ask_file : string option =
    let dialog = GWindow.file_chooser_dialog
        ~icon:Icon.icon_pixbuf
        ~action:`OPEN
        ~title:((*utf8*)(s_ "Choose the document to import"))
        ~modal:true ()
    in
    dialog#add_button_stock `CANCEL `CANCEL;
    dialog#add_button_stock `OK `OK;
    dialog#unselect_all;
    dialog#add_filter
      (GFile.filter
         ~name:(s_ "Texts (PDF, PostScript, DVI, HTML, text)")
         ~patterns:["*.pdf"; "*.ps"; "*.dvi"; "*.text"; "*.txt"; "*.html"; "*.htm"; "README";
                    (s_ "README") (* it's nice to also support something like LISEZMOI... *)]
         ());
    dialog#set_default_response `OK;
    (* --- *)
    (match dialog#run () with
      `OK ->
        (match dialog#filename with
          Some result ->
            dialog#destroy ();
            Log.printf1 "* Ok: \"%s\"\n" result;
            Some result
        | None -> begin
            dialog#destroy ();
            Log.printf "* No document was selected\n";
            None
          end)
    | _ ->
        dialog#destroy ();
        Log.printf "* You cancelled\n";
        None)

  method private file_to_format pathname =
    if Filename.check_suffix pathname ".html" ||
      Filename.check_suffix pathname ".htm" ||
      Filename.check_suffix pathname ".HTML" ||
      Filename.check_suffix pathname ".HTM" then
      "html"
    else if Filename.check_suffix pathname ".text" ||
      Filename.check_suffix pathname ".txt" ||
      Filename.check_suffix pathname "readme" ||
      Filename.check_suffix pathname "lisezmoi" ||
      Filename.check_suffix pathname ".TEXT" ||
      Filename.check_suffix pathname ".TXT" ||
      Filename.check_suffix pathname "README" ||
      Filename.check_suffix pathname "LISEZMOI" then
      "text"
    else if Filename.check_suffix pathname ".ps" ||
      Filename.check_suffix pathname ".eps" ||
      Filename.check_suffix pathname ".PS" ||
      Filename.check_suffix pathname ".EPS" then
      "ps"
    else if Filename.check_suffix pathname ".dvi" ||
      Filename.check_suffix pathname ".DVI" then
      "dvi"
    else if Filename.check_suffix pathname ".pdf" ||
      Filename.check_suffix pathname ".PDF" then
      "pdf"
    else
      failwith ("I cannot recognize the file type of " ^ pathname);

  method private format_to_reader format =
    match format with
    | "pdf"  -> Configuration.extract_string_variable_or ~default:"evince" "MARIONNET_PDF_READER"
    | "ps"   -> Configuration.extract_string_variable_or ~default:"evince" "MARIONNET_POSTSCRIPT_READER"
    | "dvi"  -> Configuration.extract_string_variable_or ~default:"evince" "MARIONNET_DVI_READER"
      (* 'file' may recognize (X)HTML as XML... *)
    | "html" -> Configuration.extract_string_variable_or ~default:"galeon" "MARIONNET_HTML_READER"
    | "text" -> Configuration.extract_string_variable_or ~default:"emacs"  "MARIONNET_TEXT_EDITOR"
      (* the file type in unknown: web browsers can open most everything... *)
    | "auto" -> Configuration.extract_string_variable_or ~default:"galeon" "MARIONNET_HTML_READER"
    | _ ->
      failwith ("The format \"" ^ format ^ "\" is not supported");

  (** Import the given file, copying it into the appropriate directory with a fresh name;
      return the fresh name (just the file name, not a complete pathname) and the name
      of an application suitable to read it, as a pair. In case of failure show an error
      message and raise an exception. If ~move is true then the file is moved instead of
      copied. *)
  method private import_file ?(move=false) pathname =
    try
      let file_format    = self#file_to_format pathname in
      let parent         = self#directory in
      let fresh_pathname = UnixExtra.temp_file ~parent ~prefix:"document-" () in
      let fresh_name     = Filename.basename fresh_pathname in
      let result         = (fresh_name, file_format) in
     (try
      (match move with
      | false -> UnixExtra.file_copy pathname fresh_pathname
      | true  -> UnixExtra.file_move pathname fresh_pathname
      );
      UnixExtra.set_perm ~a:() ~w:false fresh_pathname;
      Log.Command.ll fresh_pathname;
      result
      with Unix.Unix_error (_,_, _) ->
       begin
         UnixExtra.apply_ignoring_Unix_error Unix.unlink fresh_pathname;
         let title =
           Printf.sprintf "Failed copying the file \n\"%s\"\n" pathname in
         failwith title;
       end)
     with (Failure title) as e -> begin
      Simple_dialogs.error title error_message ();
      raise e (* Re-raise *)
    end

  method import_report ~machine_or_router_name ~pathname () =
    let title = (s_ "Report on ") ^ machine_or_router_name in
    let row_id = self#import_document ~move:true pathname in
    self#set_row_title   row_id title;
    self#set_row_author  row_id "-";
    self#set_row_type    row_id (s_ "Report");
    self#set_row_comment row_id ((s_ "created on ") ^ (UnixExtra.date ~dot:" " ()));

  method import_history ~machine_or_router_name ~pathname () =
    let title = (s_ "History of ") ^ machine_or_router_name in
    let row_id = self#import_document ~move:true pathname in
    self#set_row_title   row_id title;
    self#set_row_author  row_id "-";
    self#set_row_type    row_id (s_ "History");
    self#set_row_comment row_id ((s_ "created on ") ^ (UnixExtra.date ~dot:" " ()));

  method import_document ?(move=false) user_path_name =
    let internal_file_name, format = self#import_file user_path_name in
    let row_id =
      self#add_row
        [ filename_header, Row_item.String internal_file_name;
          format_header,   Row_item.String format ]
    in
    let title = Filename.chop_extension (Filename.basename user_path_name) in
    let otype = FilenameExtra.get_extension user_path_name in
    let oauth = get_full_user_name () in
    let () = self#set_row_title (row_id) title in
    let () = Option.iter (self#set_row_type   row_id) otype in
    let () = Option.iter (self#set_row_author row_id) oauth in
    row_id

  initializer
    let _ =
      self#add_icon_column
        ~header:icon_header
        ~shown_header:(s_ "Icon")
        ~strings_and_pixbufs:[ "text", Initialization.Path.images^"treeview-icons/text.xpm"; ]
        ~default:(fun () -> Row_item.Icon "text")
        () in
    let _ =
      self#add_editable_string_column
        ~header:title_header
        ~shown_header:(s_ "Title")
        ~italic:true
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_editable_string_column
        ~header:author_header
        ~shown_header:(s_ "Author")
        ~italic:false
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_editable_string_column
        ~header:type_header
        ~shown_header:(s_ "Type")
        ~italic:false
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_editable_string_column
        ~shown_header:(s_ "Comment")
        ~header:"Comment"
        ~italic:true
        ~default:(fun () -> Row_item.String "Please edit this")
        () in
    let _ =
      self#add_string_column
        ~header:"FileName"
        ~hidden:true
        () in
    let _ =
      self#add_string_column
        ~header:"Format"
        ~default:(fun () -> Row_item.String "auto") (* unknown format; this is usefule for
                                              backward-compatibility, as this column
                                              didn't exist in older Marionnet versions *)
        ~hidden:true
        () in
    (* Make internal data structures: no more columns can be added now: *)
    self#create_store_and_view;

    (* Setup the contextual menu: *)
    self#set_contextual_menu_title "Texts operations";
    self#add_menu_item
      (s_ "Import a document")
      (fun _ -> true)
      (fun _ ->
        ignore (Option.map self#import_document self#ask_file));

    self#add_menu_item
      (s_ "Display this document")
      Option.to_bool
      (fun selected_rowid_if_any ->
        let row_id = Option.extract selected_rowid_if_any in
        self#display row_id);
    self#set_double_click_on_row_callback (fun row_id -> self#display row_id);

    self#add_menu_item
      (s_ "Remove this document")
      Option.to_bool
      (fun selected_rowid_if_any ->
        let row_id = Option.extract selected_rowid_if_any in
        let file_name = (self#get_row_filename row_id) in
        let pathname = Filename.concat (self#directory) (file_name) in
        UnixExtra.apply_ignoring_Unix_error Unix.unlink pathname;
        self#remove_row row_id;
        );

     (* J.V. *)
     self#set_after_update_callback after_user_edit_callback;

end;;

class treeview = t
module The_unique_treeview = Stateful_modules.Variable (struct
  type t = treeview
  let name = Some "treeview_documents"
  end)
let extract = The_unique_treeview.extract


(* Add the button "Import" at right side of the treeview. *)
let add_import_button ~(window:GWindow.window) ~(hbox:GPack.box) ~(toolbar:GButton.toolbar) (treeview:t) : unit =
  (*let packing = toolbar#add in*)
  let packing = Gui_bricks.make_toolbar_packing_function (toolbar) in
  (* --- *)
  let b = Gui_bricks.button_image (*~window*) ~packing ~stock:`ADD ~stock_size:`SMALL_TOOLBAR ~tooltip:(s_ "Import a document") () in
  (* --- *)
  (* Behaviour on click: *)
  let callback () = ignore (Option.map treeview#import_document treeview#ask_file) in
  let () = ignore (b#connect#clicked ~callback) in
  ()

let make ~(window:GWindow.window) ~(hbox:GPack.box) ~after_user_edit_callback ~method_directory ~method_filename () =
  let result = new t ~packing:(hbox#add) ~after_user_edit_callback ~method_directory ~method_filename () in
  let toolbar = Treeview.add_expand_and_collapse_button ~window ~hbox (result:>Treeview.t) in
  let _import = add_import_button ~window ~hbox ~toolbar (result) in
  The_unique_treeview.set result;
  result
;;

