local U = {}
function U.copy(t)
  if type(t)~='table' then return t end
  local r={}; for k,v in pairs(t) do r[k]=U.copy(v) end; return r
end
function U.rng(seed)
  local r={seed=(math.floor(tonumber(seed) or 12345)%2147483647)}
  if r.seed==0 then r.seed=1 end
  function r:random(n)
    self.seed=(self.seed*48271)%2147483647
    if n then assert(n>0); return (self.seed%n)+1 end
    return self.seed/2147483647
  end
  function r:shuffle(t)
    for i=#t,2,-1 do local j=self:random(i);t[i],t[j]=t[j],t[i] end
  end
  return r
end
function U.remove(t,item)
  for i,v in ipairs(t) do if v==item then table.remove(t,i); return true end end
  return false
end
function U.contains(t,item)
  for _,v in ipairs(t) do if v==item then return true end end
  return false
end
function U.count(t) local n=0;for _ in pairs(t) do n=n+1 end; return n end
function U.sortedkeys(t)
  local a={};for k in pairs(t) do a[#a+1]=k end
  table.sort(a,function(x,y)return tostring(x)<tostring(y) end);return a
end
return U
