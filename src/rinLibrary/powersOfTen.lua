-------------------------------------------------------------------------------
-- Powers of Ten table.
-- @module rinLibrary.powersOfTen
-- @author Pauli
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- @table powersOfTen
-- A table containing integral powers of ten then their reciprocals.
--
-- This is implemented as a memo function so as to avoid an expensive
-- exponentiation or repeatitive sequences of multiplications.  The maximum
-- recursion depth is O(log k) during calculation.  We also populate some
-- small positive integral values because they are the most likely to be
-- requied and this saves a small amount of computation.
return
    setmetatable({ 10, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, [0] = 1 },
        { __index = function (t, k)
                        if k < 0 then
                            t[k] = 1 / t[-k]
                        elseif k % 2 == 1 then
                            t[k] = 10 * t[k-1]
                        else
                            local z = t[k/2]
                            t[k] = z * z
                        end
                        return t[k]
                    end
        } )

