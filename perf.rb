#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__) + '/lib'
require 'perf/bisect'

Perf::Bisect.new.run(
  '784e9017b8fe93bd1f23689509ec1dc2b25d4f6c',
  '6606aa80ec7a81085bc062655f239699dd24f1ff'
)
