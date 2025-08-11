(* This file is part of our reusable OCaml BRICKS library
   Copyright (C) 2019  Jean-Vincent Loddo

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

(* Do not remove the following comment: it's an ocamldoc workaround. *)
(** *)

type multiplicity = int

(** The abstract type of an hashmset.
    The mutable identifier (id) and the integer associated to each key are introduced
    only to render the function `to_list' stable (see the comment below): *)
type 'a t = { table : ('a, int * multiplicity) Table.t; mutable id : int }

(** The hashmset constructor. *)
let make ?weak ?identifier ?equality ?size () : 'a t = { table=(Table.make ?weak ?identifier ?equality ?size ()); id=0; }

let to_hashtbl hs = hs.table#to_hashtbl

(** The member predicate. *)
let mem (hs:'a t) (x:'a) = hs.table#mem x

let multiplicity (hs:'a t) (x:'a) =
  try
    let (id, mult) = hs.table#find x in
    mult
  with Not_found -> 0

(** Add (or remove, if quantity<0) a member to the hashmset. *)
let add ?(quantity=1) (hs:'a t) (x:'a) =
  try
    let (id, mult) = hs.table#find x in
    let mult = mult + quantity in
    if mult <= 0 then
      hs.table#remove x
    else
      hs.table#replace x (id, mult)
  (* --- *)
  with Not_found ->
    if quantity <= 0 then () (* ignore *) else (* continue: *)
    let card = hs.id in
    let () = hs.table#add x (card, quantity) in
    let () = hs.id <- card + 1 in
    ()

(** Remove a member from the hashmset. *)
let remove ?(quantity=1) (hs:'a t) (x:'a) =
  add ~quantity:(-quantity) hs x

(** Make an hashmset from a list. *)
let of_list ?weak ?identifier ?equality ?size (l:'a list) : 'a t =
  let n = List.length l in
  let size = match size with Some s -> s | None -> int_of_float ((float_of_int n) /. 0.70) in
  let hs = make ?weak ?identifier ?equality ~size () in
  let () = (List.iter (add hs) l) in
  hs

(** Make an hashmset from an array. *)
let of_array ?weak ?identifier ?equality ?size (xs:'a array) : 'a t =
  let n = Array.length xs in
  let size = match size with Some s -> s | None -> int_of_float ((float_of_int n) /. 0.70) in
  let hs = make ?weak ?identifier ?equality ~size () in
  let () = (Array.iter (add hs) xs) in
  hs

let to_list_unstable (hs:'a t) =
  hs.table#fold (fun x (id,mult) xs -> (x,mult)::xs) []

(* To render this function stable, we have to sort the extracted elements
    using the associated identifier, which is incremented each time an
    element is added. In this way, we are able to return the list of elements
    in the order of insertions. *)
let to_list_stable (hs:'a t) =
  let jxs = hs.table#fold (fun x j jxs -> (j,x)::jxs) [] in
  let jxs = List.fast_sort (compare) jxs in
  List.map (fun ((id,mult), x) -> (x,mult)) jxs

(* Use ~unstable:() to speed up the answer, when the stability is not relevant. *)
let to_list ?unstable =
  match unstable with
  | None    -> to_list_stable
  | Some () -> to_list_unstable

let to_array ?unstable (hs:'a t) =
  Array.of_list (to_list ?unstable hs)
