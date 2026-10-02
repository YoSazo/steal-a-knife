--!strict
-- Big-number formatting shared by the HUD and server messages: 1.5K, 2.3M ... 4.1Qn, 7Sx, up to
-- Vigintillion (Vg), then scientific notation. Money goes into the quintillions and beyond.

local Format = {}

local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qd",
	"Qn",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nvd",
	"Vg",
}

-- 1234 -> "1.2K", 999 -> "999", 1e18 -> "1Qn"
function Format.Short(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local text
	if n >= 1000 then
		text = string.format("%.2e", n * 1000 ^ (i - 1))
	elseif i == 1 then
		text = tostring(math.floor(n))
	elseif n >= 100 then
		text = string.format("%d%s", math.floor(n), SUFFIXES[i])
	else
		-- 1.5K, 12.3M; drop a trailing ".0"
		text = (string.format("%.1f", math.floor(n * 10) / 10):gsub("%.0$", "")) .. SUFFIXES[i]
	end
	return if negative then "-" .. text else text
end

-- "$1.5K"
function Format.Cash(n: number): string
	return "$" .. Format.Short(n)
end

return Format
