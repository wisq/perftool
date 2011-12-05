#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__) + '/lib'
require 'perf/bisect'

Perf::Bisect.new.run(
  'fdfac297cdcbeb0323542bc387c93224a432c941',
  '6606aa80ec7a81085bc062655f239699dd24f1ff'
)
