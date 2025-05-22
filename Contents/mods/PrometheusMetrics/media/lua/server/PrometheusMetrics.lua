-- Only for MP, server side
if not isServer() then
	return
end

-- ProjectZomboid Prometheus metrics served at /metrics

-- GLOBAL
local totalZombieKills = 0
local weaponHits = {} -- contador por arma: { ["Base.Axe"] = 10, ... }
local weaponKills = {} -- contador de muertes por arma
local playerDeaths = {} -- guarda tiempos de conexión y muerte para calcular tiempo de vida
local totalLifetime = 0
local deathCount = 0

-- Callbacks
Events.OnZombieDead.Add(function(zombie)
	-- Cada vez que un zombie muere, incrementamos el contador global
	totalZombieKills = totalZombieKills + 1
end)

Events.OnHitZombie.Add(function(zombie, attacker, bodyPart, weapon)
	if not attacker or not attacker:isLocalPlayer() then
		return
	end
	local player = attacker -- IsoPlayer
	local weaponType = "None"
	if weapon then
		weaponType = weapon:getFullType() or weapon:getName() or "Unknown"
	end
	-- Incrementar conteo de impactos por arma
	weaponHits[weaponType] = (weaponHits[weaponType] or 0) + 1

	-- Verificar si con este golpe el zombie murió
	if zombie:getHealth() <= 0 then
		weaponKills[weaponType] = (weaponKills[weaponType] or 0) + 1
		-- También podríamos incrementar kills por jugador usando player:getZombieKills()
		-- player:getZombieKills() se actualiza automáticamente
	end
end)

Events.OnPlayerDeath.Add(function(player)
	-- Registrar tiempo de vida de jugador
	local spawnTime = playerDeaths[player:getUsername()]
	if spawnTime then
		local life = getGameTime():getTimestamp() - spawnTime
		totalLifetime = totalLifetime + life
		deathCount = deathCount + 1
		playerDeaths[player:getUsername()] = nil
	end
end)

Events.OnPlayerConnected.Add(function(player)
	-- Registrar hora de conexión (simulando tiempo de vida inicial)
	playerDeaths[player:getUsername()] = getGameTime():getTimestamp()
end)

-- Función para generar el texto Prometheus de /metrics
local function formatMetrics()
	local lines = {}
	-- Jugadores actuales
	local onlinePlayers = #getOnlinePlayers()
	table.insert(lines, "# HELP pz_players_active Number of active players")
	table.insert(lines, "# TYPE pz_players_active gauge")
	table.insert(lines, string.format("pz_players_active %d", onlinePlayers))

	-- Zombis muertos totales
	table.insert(lines, "# HELP pz_zombies_killed_total Total zombies killed")
	table.insert(lines, "# TYPE pz_zombies_killed_total counter")
	table.insert(lines, string.format("pz_zombies_killed_total %d", totalZombieKills))

	-- Tiempo de vida promedio
	local avgLife = deathCount > 0 and (totalLifetime / deathCount) or 0
	table.insert(lines, "# HELP pz_avg_lifetime Average lifetime of players")
	table.insert(lines, "# TYPE pz_avg_lifetime gauge")
	table.insert(lines, string.format("pz_avg_lifetime %.2f", avgLife))

	-- Salud promedio
	local sumHealth = 0
	local players = getOnlinePlayers()
	for i = 1, #players do
		sumHealth = sumHealth + players[i]:getHealth()
	end
	local avgHealth = (#players > 0) and (sumHealth / #players) or 0
	table.insert(lines, "# HELP pz_avg_health Average health of players")
	table.insert(lines, "# TYPE pz_avg_health gauge")
	table.insert(lines, string.format("pz_avg_health %.2f", avgHealth))

	-- Clima: temperatura (usando primer jugador como referencia) y lluvia
	if #players > 0 then
		local temp = getClimateManager():getAirTemperatureForCharacter(players[1], false)
		local raining = getClimateManager():isRaining() and 1 or 0
		local rainInt = getClimateManager():getRainIntensity()
		table.insert(lines, "# HELP pz_temperature Current air temperature")
		table.insert(lines, "# TYPE pz_temperature gauge")
		table.insert(lines, string.format("pz_temperature %.2f", temp))
		table.insert(lines, "# HELP pz_rain_intensity Current rain intensity (0 to 1)")
		table.insert(lines, "# TYPE pz_rain_intensity gauge")
		table.insert(lines, string.format("pz_rain_intensity %.2f", rainInt))
		table.insert(lines, "# HELP pz_is_raining Whether it is currently raining (0 or 1)")
		table.insert(lines, "# TYPE pz_is_raining gauge")
		table.insert(lines, string.format("pz_is_raining %d", raining))
	end

	-- Métricas por jugador: hambre, sed, infección, zombis muertos
	for i = 1, #players do
		local p = players[i]
		local name = p:getUsername()
		local hunger = p:getStats():getHunger()
		local thirst = p:getStats():getThirst()
		local infected = p:getBodyDamage():isInfected() and 1 or 0
		local kills = p:getZombieKills()
		table.insert(lines, string.format('# HELP pz_player_hunger Hunger level of player "%s"', name))
		table.insert(lines, "# TYPE pz_player_hunger gauge")
		table.insert(lines, string.format('pz_player_hunger{player="%s"} %.2f', name, hunger))
		table.insert(lines, string.format('# HELP pz_player_thirst Thirst level of player "%s"', name))
		table.insert(lines, "# TYPE pz_player_thirst gauge")
		table.insert(lines, string.format('pz_player_thirst{player="%s"} %.2f', name, thirst))
		table.insert(lines, string.format('# HELP pz_player_health Health of player "%s"', name))
		table.insert(lines, "# TYPE pz_player_health gauge")
		table.insert(lines, string.format('pz_player_health{player="%s"} %.2f', name, p:getHealth()))
		table.insert(lines, string.format('# HELP pz_player_infected Whether player "%s" is infected (1 or 0)', name))
		table.insert(lines, "# TYPE pz_player_infected gauge")
		table.insert(lines, string.format('pz_player_infected{player="%s"} %d', name, infected))
		table.insert(lines, string.format('# HELP pz_player_zombie_kills_total Total zombies killed by "%s"', name))
		table.insert(lines, "# TYPE pz_player_zombie_kills_total counter")
		table.insert(lines, string.format('pz_player_zombie_kills_total{player="%s"} %d', name, kills))
	end

	-- Uso de armas y muertes por arma
	table.insert(lines, "# HELP pz_weapon_hits_total Total weapon hits by type")
	table.insert(lines, "# TYPE pz_weapon_hits_total counter")
	for weap, count in pairs(weaponHits) do
		table.insert(lines, string.format('pz_weapon_hits_total{weapon="%s"} %d', weap, count))
	end
	table.insert(lines, "# HELP pz_weapon_kills_total Total kills by weapon type")
	table.insert(lines, "# TYPE pz_weapon_kills_total counter")
	for weap, count in pairs(weaponKills) do
		table.insert(lines, string.format('pz_weapon_kills_total{weapon="%s"} %d', weap, count))
	end

	return table.concat(lines, "\n")
end

-- Configurar servidor HTTP para /metrics
local HttpServer = luajava.bindClass("com.sun.net.httpserver.HttpServer")
local InetSocketAddress = luajava.bindClass("java.net.InetSocketAddress")
local server = HttpServer.create(InetSocketAddress(9090), 0)
-- Manejador de solicitudes HTTP
server:createContext(
	"/metrics",
	luajava.newInstance("com.sun.net.httpserver.HttpHandler", {
		handle = function(exchange)
			local response = formatMetrics()
			local bytes = response:getBytes() -- asumiendo función getBytes en JavaString
			exchange:getResponseHeaders():set("Content-Type", "text/plain; version=0.0.4")
			exchange:sendResponseHeaders(200, bytes:len())
			exchange:getResponseBody():write(bytes)
			exchange:getResponseBody():close()
		end,
	})
)
server:setExecutor(nil) -- usa el executor por defecto
server:start()

print("Prometheus metrics server started on port 9090")
