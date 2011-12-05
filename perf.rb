#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__) + '/lib'
require 'perf/bisect'

pb = Perf::Bisect.new.run(
  :first => 'fdfac297cdcbeb0323542bc387c93224a432c941',
  :last  => 'c209dc3dda29f909e28a129d49724e2047848d4d',
  :interesting => %w{
    124b982 51d35ec 073ffa3 4884343 2f39555 91d0d10 8a66d2d 779a05a
    c76ff15 f8a4259 08f7f38 0860fc6 213247b 30ea264 310b1ab
  }
)
