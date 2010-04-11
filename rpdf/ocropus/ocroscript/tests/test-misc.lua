dofile("utest.lua")

section "1D"
st = bytearray:new()
st:push(0)
st:push(1)
st:push(2)
test_assert(st:length()==3)
test_assert(st:at(1)==1)
test_failure(function() st:at(1,1) end,"catching 2D access of 1D array")
test_failure(function() st:at(1000) end,"catching out of bounds index")
st:put(1,111)
test_failure(function() st:at(1,1) end,"catching 2D access of 1D array")
test_failure(function() st:at(1000) end,"catching out of bounds index")
test_assert(st:at(1)==111)
section "2D"
a = floatarray:new(100,200)
test_assert(a:dim(0)==100 and a:dim(1)==200)
b = bytearray:new(50,50)
test_assert(not narray.samedims(a,b))
narray.fill(a,99)
test_assert(a:at(10,10)==99)
note(a:length1d()==100*200)
narray.copy(b,a)
test_assert(b:dim(0)==100 and b:dim(1)==200)
test_assert(b:at(3,4)==99)
test_failure(function() b:at(0) end,"catching 1D access of 2D array")
-- test_assert(samedims(a,b))
-- test_assert(equal(a,b))
section "read_image_gray"
read_image_gray(b,"images/simple.png")
test_assert(b:dim(0)==640 and b:dim(1)==480)
collectgarbage()
