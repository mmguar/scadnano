import 'dart:math';

import 'package:collection/collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_collection/built_collection.dart';

import 'package:scadnano/src/state/loopout.dart';
import 'package:scadnano/src/state/potential_vertical_crossover.dart';
import 'package:scadnano/src/state/selectable.dart';
import 'crossover.dart';
import 'dna_end.dart';
import 'grid_position.dart';
import '../json_serializable.dart';
import 'strand.dart';
import 'bound_substrand.dart';
import 'helix.dart';
import 'grid.dart';
import '../util.dart' as util;
import '../constants.dart' as constants;
import 'substrand.dart';

part 'dna_design.g.dart';

//TODO: create mismatches field in DNADesign that can be accessed directly by DesignMainMismatches instead of
// going through list of all Strands

abstract class DNADesign implements Built<DNADesign, DNADesignBuilder>, JSONSerializable {
  DNADesign._();

  factory DNADesign([void Function(DNADesignBuilder) updates]) => _$DNADesign((d) => d
    ..version = constants.CURRENT_VERSION
    ..grid = Grid.square
    ..helices.replace([])
    ..strands.replace([]));

  /****************************** end built_value boilerplate ******************************/

  String get version;

  Grid get grid;

  @nullable
  int get major_tick_distance;

  BuiltList<Helix> get helices;

  BuiltList<Strand> get strands;

  @memoized
  bool get is_origami {
    for (var strand in strands) {
      if (strand.is_scaffold) {
        return true;
      }
    }
    return false;
  }

  @memoized
  BuiltMap<String, Strand> get strands_by_id {
    var builder = MapBuilder<String, Strand>();
    for (var strand in strands) {
      builder[strand.id()] = strand;
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, BoundSubstrand> get bound_substrands_by_id {
    var builder = MapBuilder<String, BoundSubstrand>();
    for (var strand in strands) {
      for (var bound_substrand in strand.bound_substrands()) {
        builder[bound_substrand.id()] = bound_substrand;
      }
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, Loopout> get loopouts_by_id {
    var builder = MapBuilder<String, Loopout>();
    for (var strand in strands) {
      for (var loopout in strand.loopouts()) {
        builder[loopout.id()] = loopout;
      }
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, Crossover> get crossovers_by_id {
    var builder = MapBuilder<String, Crossover>();
    for (var strand in strands) {
      for (var crossover in strand.crossovers) {
        builder[crossover.id()] = crossover;
      }
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, DNAEnd> get ends_by_id {
    var builder = MapBuilder<String, DNAEnd>();
    for (var strand in strands) {
      for (var bound_substrand in strand.bound_substrands()) {
        builder[bound_substrand.dnaend_start.id()] = bound_substrand.dnaend_start;
        builder[bound_substrand.dnaend_end.id()] = bound_substrand.dnaend_end;
      }
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, DNAEnd> get ends_5p_strand_by_id {
    var builder = MapBuilder<String, DNAEnd>();
    for (var strand in strands) {
      var end = strand.dnaend_5p;
      builder[end.id()] = end;
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, DNAEnd> get ends_3p_strand_by_id {
    var builder = MapBuilder<String, DNAEnd>();
    for (var strand in strands) {
      var end = strand.dnaend_3p;
      builder[end.id()] = end;
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, DNAEnd> get ends_5p_other_by_id {
    var builder = MapBuilder<String, DNAEnd>();
    for (var strand in strands) {
      for (var bound_substrand in strand.bound_substrands()) {
        var end = bound_substrand.dnaend_5p;
        if (!bound_substrand.is_first) {
          builder[end.id()] = end;
        }
      }
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, DNAEnd> get ends_3p_other_by_id {
    var builder = MapBuilder<String, DNAEnd>();
    for (var strand in strands) {
      for (var bound_substrand in strand.bound_substrands()) {
        var end = bound_substrand.dnaend_3p;
        if (!bound_substrand.is_last) {
          builder[end.id()] = end;
        }
      }
    }
    return builder.build();
  }

  @memoized
  BuiltMap<String, Selectable> get selectable_by_id {
    Map<String, Selectable> map = {};
    for (var map_small in [strands_by_id, loopouts_by_id, crossovers_by_id, ends_by_id]) {
      for (var key in map_small.keys) {
        var obj = map_small[key];
        map[key] = obj;
      }
    }
    return map.build();
  }

  @memoized
  BuiltMap<BoundSubstrand, BuiltList<Mismatch>> get substrand_mismatches_map {
    var substrand_mismatches_map_builder = MapBuilder<BoundSubstrand, ListBuilder<Mismatch>>();
    for (Strand strand in this.strands) {
      if (strand.dna_sequence != null) {
        for (BoundSubstrand bound_ss in strand.bound_substrands()) {
          substrand_mismatches_map_builder[bound_ss] = this._find_mismatches_on_substrand(bound_ss);
        }
      }
    }
    var substrand_mismatches_builtmap_builder = MapBuilder<BoundSubstrand, BuiltList<Mismatch>>();
    substrand_mismatches_map_builder.build().forEach((bound_ss, mismatches) {
      substrand_mismatches_builtmap_builder[bound_ss] = mismatches.build();
    });
    return substrand_mismatches_builtmap_builder.build();
  }

  @memoized
  BuiltMap<DNAEnd, BoundSubstrand> get end_to_substrand {
    var end_to_substrand_builder = MapBuilder<DNAEnd, BoundSubstrand>();
    for (var strand in strands) {
      for (var substrand in strand.bound_substrands()) {
        end_to_substrand_builder[substrand.dnaend_3p] = substrand;
        end_to_substrand_builder[substrand.dnaend_5p] = substrand;
      }
    }
    return end_to_substrand_builder.build();
  }

  @memoized
  BuiltMap<Substrand, Strand> get substrand_to_strand {
    var substrand_to_strand_builder = MapBuilder<Substrand, Strand>();
    for (var strand in strands) {
      for (var substrand in strand.substrands) {
        substrand_to_strand_builder[substrand] = strand;
      }
    }
    return substrand_to_strand_builder.build();
  }

  @memoized
  BuiltMap<Crossover, Strand> get crossover_to_strand {
    var crossover_to_strand_builder = MapBuilder<Crossover, Strand>();
    for (var strand in strands) {
      for (var crossover in strand.crossovers) {
        crossover_to_strand_builder[crossover] = strand;
      }
    }
    return crossover_to_strand_builder.build();
  }

  Strand loopout_to_strand(Loopout loopout) => substrand_to_strand[loopout];

  Strand end_to_strand(DNAEnd end) => substrand_to_strand[end_to_substrand[end]];

  @memoized
  BuiltList<BuiltList<BoundSubstrand>> get helix_idx_to_substrands {
    return construct_helix_idx_to_substrands_map(helices.length, strands);
  }

  @memoized
  bool get helices_view_order_is_identity {
    for (var helix in helices) {
      if (helix.idx != helix.view_order) {
        return false;
      }
    }
    return true;
  }

  static _default_svg_position(int idx) => Point<num>(0, constants.DISTANCE_BETWEEN_HELICES_SVG * idx);

  static _default_grid_position(int idx) => GridPosition(0, idx);

  @memoized
  BuiltMap<GridPosition, dynamic> get gp_to_helix {
    var map_builder = MapBuilder<GridPosition, Helix>();
    for (var helix in helices) {
      map_builder[helix.grid_position] = helix;
    }
    return map_builder.build();
  }

  /// Gets DNAEnd at given address (helix,offset,forward)
  /// Offset is inclusive, i.e., dna_end.offset_inclusive
  @memoized
  BuiltMap<Address, DNAEnd> get address_to_end {
    var map = Map<Address, DNAEnd>();
    for (var strand in strands) {
      for (var ss in strand.bound_substrands()) {
        for (var end in [ss.dnaend_start, ss.dnaend_end]) {
          var key = Address(helix_idx: ss.helix, offset: end.offset_inclusive, forward: ss.forward);
          map[key] = end;
        }
      }
    }
    return map.build();
  }

  /// Gets Strand with 5p end at given address (helix,offset,forward)
  /// Offset is inclusive, i.e., dna_end.offset_inclusive
  @memoized
  BuiltMap<Address, Strand> get address_5p_to_strand {
    var map = Map<Address, Strand>();
    for (var strand in strands) {
      var ss = strand.first_bound_substrand();
      var key = Address(helix_idx: ss.helix, offset: ss.dnaend_5p.offset_inclusive, forward: ss.forward);
      map[key] = strand;
    }
    return map.build();
  }

  /// Gets Strand with 5p end at given address (helix,offset,forward)
  /// Offset is inclusive, i.e., dna_end.offset_inclusive
  @memoized
  BuiltMap<Address, Strand> get address_3p_to_strand {
    var map = Map<Address, Strand>();
    for (var strand in strands) {
      var ss = strand.last_bound_substrand();
      var key = Address(helix_idx: ss.helix, offset: ss.dnaend_3p.offset_inclusive, forward: ss.forward);
      map[key] = strand;
    }
    return map.build();
  }

  /// Maps Addresses to PotentialVerticalCrossovers.
  /// The end on TOP (i.e., lower helix idx) has the address with the key in the map.
  @memoized
  BuiltList<PotentialVerticalCrossover> get potential_vertical_crossovers {
    List<PotentialVerticalCrossover> crossovers = [];
    for (var strand_5p in strands) {
      var ss = strand_5p.first_bound_substrand();
      int helix_idx = ss.helix;
      int offset = ss.dnaend_5p.offset_inclusive;
      bool forward = ss.forward;
      var address_5p = Address(helix_idx: helix_idx, offset: offset, forward: forward);
      for (var address_3p in [
        Address(helix_idx: helix_idx - 1, offset: offset, forward: !forward),
        Address(helix_idx: helix_idx + 1, offset: offset, forward: !forward)
      ]) {
        int helix_idx_top;
        int helix_idx_bot;
        var address_top;
        bool forward_top;
        BoundSubstrand substrand_top;
        BoundSubstrand substrand_bot;
        DNAEnd dna_end_top;
        DNAEnd dna_end_bot;
        if (address_3p_to_strand.keys.contains(address_3p)) {
          Strand strand_3p = address_3p_to_strand[address_3p];
          if (strand_5p != strand_3p) {
            if (helix_idx + 1 == address_3p.helix_idx) {
              // 5' end is on top, 3' is on bottom
              helix_idx_top = address_5p.helix_idx;
              address_top = address_5p;
              forward_top = forward;
              substrand_top = ss;
              dna_end_top = substrand_top.dnaend_5p;

              helix_idx_bot = address_3p.helix_idx;
              substrand_bot = strand_3p.last_bound_substrand();
              dna_end_bot = substrand_bot.dnaend_3p;
            } else {
              // 3' end is on top, 5' is on bottom
              helix_idx_top = address_3p.helix_idx;
              address_top = address_3p;
              forward_top = !forward;
              substrand_top = strand_3p.last_bound_substrand();
              dna_end_top = substrand_top.dnaend_3p;

              helix_idx_bot = address_5p.helix_idx;
              substrand_bot = ss;
              dna_end_bot = substrand_bot.dnaend_5p;
            }
          }
        }
        if (helix_idx_top != null) {
          crossovers.add(PotentialVerticalCrossover(
            helix_idx_top: helix_idx_top,
            helix_idx_bot: helix_idx_bot,
            offset: offset,
            forward_top: forward_top,
            color: strand_5p.color.toHexColor().toCssString(),
            substrand_top: substrand_top,
            substrand_bot: substrand_bot,
            dna_end_top: dna_end_top,
            dna_end_bot: dna_end_bot,
          ));
        }
      }
    }
    return crossovers.build();
  }

  /// max offset allowed on any Helix in the Model
  @memoized
  int get max_offset => helices.map((helix) => helix.max_offset).reduce(max);

  /// min offset allowed on any Helix in the Model
  @memoized
  int get min_offset => helices.map((helix) => helix.min_offset).reduce(min);

  DNADesign add_strand(Strand strand) => rebuild((d) => d..strands.add(strand));

  DNADesign add_strands(Iterable<Strand> new_strands) => rebuild((d) => d..strands.addAll(new_strands));

  DNADesign remove_strand(Strand strand) => rebuild((d) => d..strands.remove(strand));

  DNADesign remove_strands(Iterable<Strand> strands_to_remove) {
    Set<Strand> strands_to_remove_set = strands_to_remove.toSet();
    return rebuild((d) => d..strands.removeWhere((strand) => strands_to_remove_set.contains(strand)));
  }

  Map<String, dynamic> to_json_serializable({bool suppress_indent = false}) {
    Map<String, dynamic> json_map = {constants.version_key: this.version};

    if (this.grid != constants.default_grid) {
//      json_map[constants.grid_key] = grid_to_json(this.grid);
      json_map[constants.grid_key] = this.grid.to_json();
    }
    if (this.major_tick_distance != grid.default_major_tick_distance()) {
      json_map[constants.major_tick_distance_key] = this.major_tick_distance;
    }

    List<dynamic> helix_jsons = json_map[constants.helices_key] = [
      for (var helix in this.helices) helix.to_json_serializable(suppress_indent: suppress_indent)
    ];
    json_map[constants.strands_key] = [
      for (var strand in this.strands) strand.to_json_serializable(suppress_indent: suppress_indent)
    ];

    for (int i = 0; i < helices.length; i++) {
      var helix = helices[i];
      var helix_json = suppress_indent ? helix_jsons[i].value : helix_jsons[i];
      if (helix.has_max_offset() && has_nondefault_max_offset(helix)) {
        helix_json[constants.max_offset_key] = helix.max_offset;
      }
      if (helix.has_min_offset() && has_nondefault_min_offset(helix)) {
        helix_json[constants.min_offset_key] = helix.min_offset;
      }
    }

    return json_map;
  }

  bool has_nondefault_max_offset(Helix helix) {
    var ends = substrands_on_helix(helix.idx).map((ss) => ss.end);
    int max_end = ends.isEmpty ? 0 : ends.reduce(max);
    return helix.max_offset != max_end;
  }

  bool has_nondefault_min_offset(Helix helix) {
    var starts = substrands_on_helix(helix.idx).map((ss) => ss.start);
    int min_start = starts.isEmpty ? null : starts.reduce(min);
    // if all offsets are nonnegative (or there are no substrands, i.e., min_start == null),
    // then default min_offset is 0; otherwise it is minimum offset
    if (min_start == null || min_start >= 0) {
      return helix.min_offset != 0;
    } else {
      return helix.min_offset != min_start;
    }
  }

  static DNADesign from_json(Map<String, dynamic> json_map) {
    if (json_map == null) return null;

    var dna_design_builder = DNADesignBuilder();

    dna_design_builder.version =
        util.get_value_with_default(json_map, constants.version_key, constants.INITIAL_VERSION);
    dna_design_builder.grid =
        util.get_value_with_default(json_map, constants.grid_key, Grid.square, transformer: Grid.valueOf);

    if (json_map.containsKey(constants.major_tick_distance_key)) {
      dna_design_builder.major_tick_distance = json_map[constants.major_tick_distance_key];
    } else if (!dna_design_builder.grid.is_none()) {
      if (dna_design_builder.grid == Grid.hex || dna_design_builder.grid == Grid.honeycomb) {
        dna_design_builder.major_tick_distance = 7;
      } else {
        dna_design_builder.major_tick_distance = 8;
      }
    }

    List<HelixBuilder> helix_builders = [];
    List<dynamic> deserialized_helices_list = json_map[constants.helices_key];
    int num_helices = deserialized_helices_list.length;

    // create HelixBuilders
    int idx = 0;
    for (var helix_json in deserialized_helices_list) {
      HelixBuilder helix_builder = Helix.from_json(helix_json);
      helix_builder.idx = idx;
      helix_builder.grid = dna_design_builder.grid;
      helix_builders.add(helix_builder);
      idx++;
    }

    // view order of helices
    var identity_permutation = util.identity_permutation(num_helices);
    List<int> helices_view_order = List<int>.from(
        util.get_value_with_default(json_map, constants.helices_view_order_key, identity_permutation));
    if (helices_view_order.length != num_helices) {
      throw IllegalDNADesignError('length of helices (${num_helices}) does not match '
          'length of helices_view_order (${helices_view_order.length})');
    }
    var helices_view_order_sorted = List<int>.from(helices_view_order);
    helices_view_order_sorted.sort();
    if (!ListEquality().equals(helices_view_order_sorted, identity_permutation)) {
      throw IllegalDNADesignError('helices_view_order = ${helices_view_order} is not a permutation');
    }
    for (int i = 0; i < helices_view_order.length; i++) {
      int i_unsorted = helices_view_order[i];
      var helix_builder = helix_builders[i_unsorted];
      int view_order = i;
      helix_builder.view_order = view_order;
//      if (helix_builder.svg_position == null) {
//        helix_builder.svg_position = DNADesign._default_svg_position(display_order);
//      }
//      if (helix_builder.grid_position == null) {
//        helix_builder.grid_position = DNADesign._default_grid_position(view_order);
//      }
    }

    // strands
    List<Strand> strands = [];
    List<dynamic> deserialized_strand_list = json_map[constants.strands_key];
    for (var strand_json in deserialized_strand_list) {
      Strand strand = Strand.from_json(strand_json);
      strands.add(strand);
    }
    dna_design_builder.strands.replace(strands);

    _set_helices_min_max_offsets(helix_builders, dna_design_builder.strands.build());

    // build Helices
    List<Helix> helices = [for (var helix_builder in helix_builders) helix_builder.build()];
    dna_design_builder.helices.replace(helices);

    var dna_design = dna_design_builder.build();
    dna_design._check_legal_design();

    return dna_design;
  }

  _check_legal_design() {
//    TODO: implement this and give reasonable error messages
  }

  String toString() =>
      """DNADesign(is_origami=$is_origami, grid=$grid, major_tick_distance=$major_tick_distance, 
  helices=$helices, 
  strands=$strands)""";

  ListBuilder<Mismatch> _find_mismatches_on_substrand(BoundSubstrand substrand) {
    var mismatches = ListBuilder<Mismatch>();

    for (int offset = substrand.start; offset < substrand.end; offset++) {
      if (substrand.deletions.contains(offset)) {
        continue;
      }

      var other_ss = this.other_substrand_at_offset(substrand, offset);
      if (other_ss == null || other_ss.dna_sequence == null) {
        continue;
      }

      // most of the time, the sequence is length 1, but we have to handle insertions
      var seq = substrand.dna_sequence_in(offset, offset);
      var other_seq = other_ss.dna_sequence_in(offset, offset);

//      this._ensure_other_substrand_same_deletion_or_insertion(substrand, other_ss, offset);
      // rather than banning single deletions/insertions outright, we'll simply declare it a mismatch
      // if they are not the same on both strands

      // other_ss has a deletion (and substrand implicitly doesn't since we would have continue'd),
      if (other_ss.deletions.contains(offset)) {
        // This throws an error if substrand has a deletion at offset.
        int dna_idx = substrand.offset_to_substrand_dna_idx(offset, substrand.forward);
        int within_insertion = seq.length == 1 ? -1 : 0;
        var mismatch = Mismatch(dna_idx, offset, within_insertion: within_insertion);
        mismatches.add(mismatch);
        continue;
      }

      int length_insertion_substrand = substrand.insertion_offset_to_length[offset];
      int length_insertion_other_ss = other_ss.insertion_offset_to_length[offset];
      if (length_insertion_substrand != length_insertion_other_ss) {
        // one has an insertion and the other doesn't, or they both have insertions of different lengths
        int dna_idx = substrand.offset_to_substrand_dna_idx(offset, substrand.forward);
        int within_insertion = seq.length == 1 ? -1 : 0;
        var mismatch = Mismatch(dna_idx, offset, within_insertion: within_insertion);
        mismatches.add(mismatch);
        continue;
      }

      // at this point, they both have an insertion here, or the both don't,
      // and if they both do, they're the same length
      assert(other_seq.length == seq.length);

      for (int idx = 0, idx_other = seq.length - 1; idx < seq.length; idx++, idx_other--) {
        if (seq.codeUnitAt(idx) != _wc(other_seq.codeUnitAt(idx_other))) {
          int dna_idx = substrand.offset_to_substrand_dna_idx(offset, substrand.forward) + idx;
          int within_insertion = seq.length == 1 ? -1 : idx;
          var mismatch = Mismatch(dna_idx, offset, within_insertion: within_insertion);
          mismatches.add(mismatch);
        }
      }
    }
    return mismatches;
  }

  /// Return other substrand at `offset` on `substrand.helix_idx`, or null if there isn't one.
  BoundSubstrand other_substrand_at_offset(BoundSubstrand substrand, int offset) {
    List<BoundSubstrand> other_substrands = this._other_substrands_overlapping(substrand);
    for (var other_ss in other_substrands) {
      if (other_ss.contains_offset(offset)) {
        assert(substrand.forward != other_ss.forward);
        return other_ss;
      }
    }
    return null;
  }

  void _ensure_other_substrand_same_deletion_or_insertion(
      BoundSubstrand substrand, BoundSubstrand other_ss, int offset) {
    if (substrand.deletions.contains(offset) && !other_ss.deletions.contains(offset)) {
      throw UnsupportedError('cannot yet handle one strand having deletion at an offset but the overlapping '
          'strand does not\nThis was found between the substrands on helix ${substrand.helix} '
          'occupying offset intervals\n'
          '(${substrand.start}, ${substrand.end}) and\n'
          '(${other_ss.start}, ${other_ss.end})');
    }
    if (substrand.contains_insertion_at(offset) && !other_ss.contains_insertion_at(offset)) {
      throw UnsupportedError('cannot yet handle one strand having insertion at an offset but the overlapping '
          'strand does not\nThis was found between the substrands on helix ${substrand.helix} '
          'occupying offset intervals\n'
          '(${substrand.start}, ${substrand.end}) and\n'
          '(${other_ss.start}, ${other_ss.end})');
    }
  }

  /// Return list of mismatches in substrand where the base is mismatched with the overlapping substrand.
  /// If a mismatch occurs outside an insertion, within_insertion = -1).
  /// If a mismatch occurs in an insertion, within_insertion = relative position within insertion (0,1,...)).
  BuiltList<Mismatch> mismatches_on_substrand(BoundSubstrand substrand) {
    var ret = this.substrand_mismatches_map[substrand];
    if (ret == null) {
      ret = BuiltList<Mismatch>();
    }
    return ret;
  }

  /// Return set of substrands on the Helix with the given index.
  BuiltList<BoundSubstrand> substrands_on_helix(int helix_idx) => helix_idx_to_substrands[helix_idx];

//  Set<BoundSubstrand> substrands_on_helix_at(int helix_idx, int offset) => helix_idx_to_substrands[helix_idx];

  /// Return [Substrand]s at [offset], INCLUSIVE on left and EXCLUSIVE on right.
  BuiltSet<BoundSubstrand> substrands_on_helix_at(int helix_idx, int offset) {
    var substrands_at_offset = SetBuilder<BoundSubstrand>({
      for (var substrand in this.helix_idx_to_substrands[helix_idx])
        if (substrand.contains_offset(offset)) substrand
    });
    return substrands_at_offset.build();
  }

  /// Return [Substrand] at [address], INCLUSIVE, or null if there is none.
  BoundSubstrand substrand_on_helix_at(Address address) {
    for (var substrand in this.helix_idx_to_substrands[address.helix_idx]) {
      if (substrand.contains_offset(address.offset) && substrand.forward == address.forward) {
        return substrand;
      }
    }
    return null;
  }

  /// Return list of Substrands overlapping `substrand`.
  List<BoundSubstrand> _other_substrands_overlapping(BoundSubstrand substrand) {
    List<BoundSubstrand> ret = [];
    var helix = this.helices[substrand.helix];
    for (var other_ss in helix_idx_to_substrands[helix.idx]) {
      if (substrand.overlaps(other_ss)) {
        ret.add(other_ss);
      }
    }
    return ret;
  }

  /// Number of bases between start and end offsets, inclusive, on the given [Helix].
  /// Accounts for substrands with insertions and deletions on [BoundSubstrand]s on this Helix, but not if they
  /// are inconsistent (on one [BoundSubstrand] but not the other).
  int helix_num_bases_between(Helix helix, int start, int end) {
    if (start > end) {
      int swap = start;
      start = end;
      end = swap;
    }

    List<BoundSubstrand> substrands_intersecting = [];
    for (var ss in this.helix_idx_to_substrands[helix.idx]) {
      if (start < ss.end && ss.start <= end) {
        substrands_intersecting.add(ss);
      }
    }

    Set<int> deletions_intersecting = {};
    Set<Insertion> insertions_intersecting = {};
    for (var ss in substrands_intersecting) {
      for (var deletion in ss.deletions) {
        if (start <= deletion && deletion <= end) {
          deletions_intersecting.add(deletion);
        }
      }
      for (var insertion in ss.insertions) {
        if (start <= insertion.offset && insertion.offset <= end) {
          insertions_intersecting.add(insertion);
        }
      }
    }

    int total_insertion_length = 0;
    for (var insertion in insertions_intersecting) {
      total_insertion_length += insertion.length;
    }

    int dna_length = end - start + 1 - deletions_intersecting.length + total_insertion_length;

    return dna_length;
  }

  /// in radians; gives rotation of backbone of strand in the forward direction, as viewed in the side view
  double helix_rotation_forward(Helix helix, int offset) {
    int num_bases;
    if (helix.rotation_anchor < offset) {
      num_bases = this.helix_num_bases_between(helix, helix.rotation_anchor, offset - 1);
    } else if (helix.rotation_anchor > offset) {
      num_bases = -this.helix_num_bases_between(helix, offset + 1, helix.rotation_anchor);
    } else {
      num_bases = 0;
    }
//    num rad = (helix.rotation + (2 * pi * num_bases / 10.5)) % (2 * pi);
//    return rad;
//    num rad = (util.to_radians(helix.rotation) + (2 * pi * num_bases / 10.5)) % (2 * pi);
//    return util.to_degrees(rad);
    num rot = (helix.rotation + (360 * num_bases / 10.5)) % (360);
    return rot;
  }

  /// in radians; rotation of forward strand  + 150 degrees
  double helix_rotation_reverse(Helix helix, int offset) =>
//      this.helix_rotation_3p(helix, offset) + (2 * pi * 150.0 / 360.0);
      this.helix_rotation_forward(helix, offset) + 150;

  bool helix_has_nondefault_max_offset(Helix helix) {
    int max_ss_offset = -1;
    for (var ss in this.helix_idx_to_substrands[helix.idx]) {
      if (max_ss_offset < ss.end) {
        max_ss_offset = ss.end;
      }
    }
    return helix.max_offset != max_ss_offset;
  }

  bool helix_has_nondefault_min_offset(Helix helix) {
    int min_ss_offset = -1;
    for (var ss in this.helix_idx_to_substrands[helix.idx]) {
      if (min_ss_offset > ss.start) {
        min_ss_offset = ss.start;
      }
    }
    return helix.min_offset != min_ss_offset;
  }

  bool helix_has_substrands(Helix helix) => this.helix_idx_to_substrands[helix.idx].isNotEmpty;

  @memoized
  BuiltList<int> get helices_view_order_inverse {
    List<int> helices_view_order_inverse = List<int>(helices.length);
    for (int i = 0; i < helices.length; i++) {
      int i_unsorted = helices[i].view_order;
      helices_view_order_inverse[i_unsorted] = i;
    }
    return helices_view_order_inverse.toBuiltList();
  }

  bool is_occupied(Address address) => substrand_on_helix_at(address) != null;

  @memoized
  int max_offset_of_strands_at(int helix_idx) {
    var substrands = helix_idx_to_substrands[helix_idx];
    int max_offset =
        substrands.isEmpty ? 0 : substrands.first.end; // in case of no substrands, max offset is 0
    for (var substrand in substrands) {
      max_offset = max(max_offset, substrand.end);
    }
    return max_offset;
  }

  @memoized
  int min_offset_of_strands_at(int helix_idx) {
    var substrands = helix_idx_to_substrands[helix_idx];
    int min_offset =
        substrands.isEmpty ? 0 : substrands.first.start; // in case of no substrands, min offset is 0
    for (var substrand in substrands) {
      min_offset = min(min_offset, substrand.start);
    }
    return min_offset;
  }
}

BuiltList<BuiltList<BoundSubstrand>> construct_helix_idx_to_substrands_map(
    int num_helices, Iterable<Strand> strands) {
  var helix_idx_to_substrands_builder = List<List<BoundSubstrand>>();
  for (int _ = 0; _ < num_helices; _++) {
    helix_idx_to_substrands_builder.add(List<BoundSubstrand>());
  }
  for (Strand strand in strands) {
    for (Substrand substrand in strand.substrands) {
      if (substrand.is_bound_substrand()) {
        var bound_ss = substrand as BoundSubstrand;
        helix_idx_to_substrands_builder[bound_ss.helix].add(bound_ss);
      }
    }
  }

  var helix_idx_to_substrands_builtset_builder = List<BuiltList<BoundSubstrand>>();
  for (var substrands in helix_idx_to_substrands_builder) {
    // sort by start offset; since the intervals are disjoint, this sorts them by end as well
    substrands.sort((ss1, ss2) => ss1.start - ss2.start);
    helix_idx_to_substrands_builtset_builder.add(substrands.build());
  }
  return helix_idx_to_substrands_builtset_builder.build();
}

_set_helices_min_max_offsets(List<HelixBuilder> helix_builders, Iterable<Strand> strands) {
  var helix_idx_to_substrands = construct_helix_idx_to_substrands_map(helix_builders.length, strands);

  for (int idx = 0; idx < helix_builders.length; idx++) {
    HelixBuilder helix_builder = helix_builders[idx];

    if (helix_builder.max_offset == null) {
      var substrands = helix_idx_to_substrands[helix_builder.idx];
      var max_offset =
          substrands.isEmpty ? 0 : substrands.first.end; // in case of no substrands, max offset is 0
      for (var substrand in substrands) {
        max_offset = max(max_offset, substrand.end);
      }
      helix_builder.max_offset = max_offset;
    }

    if (helix_builder.min_offset == null) {
      var substrands = helix_idx_to_substrands[helix_builder.idx];
      var min_offset =
          substrands.isEmpty ? 0 : substrands.first.start; // in case of no substrands, min offset is 0
      for (var substrand in substrands) {
        min_offset = min(min_offset, substrand.start);
      }
      if (min_offset > 0) {
        min_offset = 0;
      }
      helix_builder.min_offset = min_offset;
    }
  }
}

class Mismatch {
  final int dna_idx;
  final int offset;
  final int within_insertion;

  Mismatch(this.dna_idx, this.offset, {this.within_insertion = -1});

  String toString() =>
      'Mismatch(dna_idx=${this.dna_idx}, offset=${this.offset}' +
      (this.within_insertion < 0 ? ')' : ', within_insertion=${this.within_insertion})');
}

final Map<int, int> _wc_table = {
  'A'.codeUnitAt(0): 'T'.codeUnitAt(0),
  'T'.codeUnitAt(0): 'A'.codeUnitAt(0),
  'G'.codeUnitAt(0): 'C'.codeUnitAt(0),
  'C'.codeUnitAt(0): 'G'.codeUnitAt(0),
  'a'.codeUnitAt(0): 't'.codeUnitAt(0),
  't'.codeUnitAt(0): 'a'.codeUnitAt(0),
  'g'.codeUnitAt(0): 'c'.codeUnitAt(0),
  'c'.codeUnitAt(0): 'g'.codeUnitAt(0),
};

int _wc(int code_unit) {
  if (_wc_table.containsKey(code_unit)) {
    return _wc_table[code_unit];
  } else {
    return code_unit;
  }
}

class IllegalDNADesignError implements Exception {
  String cause;

  IllegalDNADesignError(this.cause);
}

class StrandError extends IllegalDNADesignError {
  StrandError(Strand strand, String the_cause) : super(the_cause) {
    var first_substrand = strand.first_bound_substrand();
    var last_substrand = strand.last_bound_substrand();

    var msg = '\n'
        'strand length        =  ${strand.dna_length()}\n'
        'DNA length           =  ${strand.dna_sequence.length}\n'
        'DNA sequence         =  ${strand.dna_sequence}'
        "strand 5' helix      =  ${first_substrand.helix}\n"
        "strand 5' end offset =  ${first_substrand.offset_5p}\n"
        "strand 3' helix      =  ${last_substrand.helix}\n"
        "strand 3' end offset =  ${last_substrand.offset_3p}\n";

    this.cause += msg;
  }
}
