# M0-WP2 Isolated+Channel probe (Tessell)
# Runs in-repo: crystal run examples/m0_isolated.cr
# Outputs a single key=value summary line for grep-based verification.

require "mutex"

main_fid = Fiber.current.object_id
main_tid = Thread.current.object_id

ch_to_iso = Channel(Int32).new
ch_from_iso = Channel(Int32).new
result_ch = Channel({UInt64, UInt64, UInt64, UInt64, Int32}).new

iso_ctx = Fiber::ExecutionContext::Isolated.new("tessell-ui") do
  iso_fid1 = Fiber.current.object_id
  iso_tid1 = Thread.current.object_id
  Fiber.yield
  iso_fid2 = Fiber.current.object_id
  iso_tid2 = Thread.current.object_id

  # Cross-context communication: receive from default context, send back +1
  spawn do
    v = ch_to_iso.receive
    ch_from_iso.send(v + 1)
  end

  # Parallel context with Mutex-synchronized increments
  mutex = Mutex.new
  count = 0
  done = Channel(Nil).new
  par = Fiber::ExecutionContext::Parallel.new("worker", 4)
  4.times do
    par.spawn do
      mutex.synchronize { count += 1 }
      done.send(nil)
    end
  end
  4.times { done.receive }
  mutex_val = count

  result_ch.send({iso_fid1, iso_tid1, iso_fid2, iso_tid2, mutex_val})
end

# Drive cross-context exchange from default context
ch_to_iso.send(41)
cross_iso = ch_from_iso.receive

iso_fid1, iso_tid1, iso_fid2, iso_tid2, mutex_val = result_ch.receive

same_fiber = (iso_fid1 == iso_fid2)
same_tid = (iso_tid1 == iso_tid2)
diff_from_main = (iso_tid1 != main_tid)

puts "main_fid=#{main_fid} main_tid=#{main_tid} iso_fid=#{iso_fid1} iso_tid=#{iso_tid1} same_fiber=#{same_fiber} same_tid=#{same_tid} diff_from_main=#{diff_from_main} cross_iso=#{cross_iso} mutex_val=#{mutex_val}"
