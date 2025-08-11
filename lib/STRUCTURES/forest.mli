(* This file is part of ocamlbricks
   Copyright (C) 2012  Jean-Vincent Loddo
   Copyright (C) 2012  Université Paris 13

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
 * - Jean-Vincent Loddo: minor changes (refactoring, comments, public interface)
 *)

(** A purely functional data structure for tree forests.
    For all iterators, the order of visit is always depth-first (pre-order), left-to-right. *)

type 'a t

type 'a tree = 'a * 'a t (** a tree is a root with the forest of its children *)
type 'a leaf = 'a        (** a leaf is a tree without children *)

val empty : 'a t
val is_empty : 'a t -> bool

val add_tree : 'a tree -> 'a t -> 'a t
val add_leaf : 'a leaf -> 'a t -> 'a t

val of_tree : 'a tree -> 'a t
val to_tree : 'a t -> 'a tree

val of_leaf : 'a leaf -> 'a t
val tree_of_leaf : 'a leaf -> 'a tree

val is_tree : 'a t -> bool
val is_leaf : 'a t -> bool

val concat : 'a t -> 'a t -> 'a t
val map    : ('a -> 'b) -> 'a t -> 'b t
val iter   : ?post_order:unit -> ?parent:'a -> ('a -> 'a option -> unit) -> 'a t -> unit
val fold   : ?post_order:unit -> ?parent:'a -> ('b -> 'a -> 'a option -> 'b) -> 'b ->  'a t -> 'b

val backprop_tree          : ('a -> 'b list -> 'b) -> 'a tree -> 'b
val backprop_tree_parallel : ('a -> 'b list -> 'b) -> 'a tree -> 'b

val backprop               : ('a -> 'b list -> 'b) -> 'a t -> 'b list
val backprop_parallel      : ('a -> 'b list -> 'b) -> 'a t -> 'b list

(** Sort all levels of the forest recursively. *)
val sort      : ('a -> 'a -> int) -> 'a t -> 'a t

(** Sort all levels of the tree recursively. *)
val sort_tree : ('a -> 'a -> int) -> 'a tree -> 'a tree

val filter                   : ('a -> bool) -> 'a t -> 'a t
val nodes_such_that          : ('a -> bool) -> 'a t -> 'a list
val parent_of_node_such_that : ('a -> bool) -> 'a t -> 'a option
val find                     : ('a -> bool) -> 'a t -> 'a
val search                   : ('a -> bool) -> 'a t -> 'a option
val search_and_replace       : ('a -> bool) -> ('a -> 'a) -> 'a t -> 'a t

val parent_of : 'a -> 'a t -> 'a option
val roots_of  : 'a t -> 'a list

val children_nodes : 'a -> 'a t -> 'a list
val child_node : 'a -> 'a t -> 'a

val descendant_nodes : 'a -> 'a t -> 'a list
val grandchildren_nodes_with_repetitions : 'a -> 'a t -> 'a list

val printable_string_of_forest :
  ?level:int -> ?string_of_node:('a -> string) -> 'a t -> string

val print_forest :
  ?level:int ->
  ?string_of_node:('a -> string) -> channel:out_channel -> 'a t -> unit

val add_tree_to_forest_for_each : ('a -> bool) -> 'a -> 'a t -> 'a t -> 'a t
val add_tree_to_forest : ('a -> bool) -> 'a -> 'a t -> 'a t -> 'a t

val to_treelist   : 'a t -> 'a tree list
val of_treelist   : 'a tree list -> 'a t

val of_forestlist : 'a t list -> 'a t
val of_list       : 'a list -> 'a t
val to_list       : 'a t -> 'a list

val tree_of_acyclic_relation : successors:('a -> 'a list) -> root:'a -> 'a tree
val of_acyclic_relation      : successors:('a -> 'a list) -> roots:('a list) -> 'a t
