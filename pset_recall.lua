-- add "pset slot selection" to scripts
-- v0.1 @sonocircuit
--
-- basic implementation / proof of concept. add to any script. adapt to needs.

g = grid.connect()

-------- variables --------

PSET_SLOTS = 8 -- specify number of pset slots
pset_list = {"none"} -- table that contains a list of pset names -> populated by build_pset_list()

-------- functions --------

-- as the slots are saved as params, they need to be consistent over any pset loading.
-- load_slot_data grabs the saved slot data and overwrites the params settings.
-- this needs to be called post params:bang() at init and in pset_callback "read"
function load_slot_data()
  local loaded_file = io.open(norns.state.data.."pset_slot_settings.data", "r")
  if loaded_file then
    local loaded_pset_data = tab.load(norns.state.data.."pset_slot_settings.data")
    for i = 1, PSET_SLOTS do
      params:set("pset_slot"..i, loaded_pset_data.slot[i])
    end
    print("pset_slot data loaded")
  else
    print("error: no pset_slot data")
  end
end

-- save the pset_slot params to file
function save_slot_data()
  local saved_pset_data = {}
  saved_pset_data.slot = {}
  for i = 1, PSET_SLOTS do
    saved_pset_data.slot[i] = params:get("pset_slot"..i)
  end
  tab.save(saved_pset_data, norns.state.data.."pset_slot_settings.data")
  print("pset_slot data saved")
end

-- build list of pset names
-- the directory norns.state.data is scanned and if an entry ends with .pset the name is extracted and insterted to the pset_name table.
-- this needs to be called at init and whenever a pset is saved or deleted.
function build_pset_list()
  local files_data = util.scandir(norns.state.data)
  pset_list = {"none"}
  for i = 1, #files_data do
    if files_data[i]:match("^.+(%..+)$") == ".pset" then
      local loaded_file = io.open(norns.state.data..files_data[i], "r")
      if loaded_file then
        io.input(loaded_file)
        local pset_name = string.sub(io.read(), 4, -1)
        table.insert(pset_list, pset_name)
        io.close(loaded_file)
      end
    end
  end
end

-- when a pset is saved, the param attributes for slot selection need to be updated.
-- this is called by pset_callbacks "save" and "delete"
function update_slot_params()
  for i = 1, PSET_SLOTS do
    local p = params:lookup_param("pset_slot"..i)
    p.options = {table.unpack(pset_list)}
    p.count = #pset_list
    p:bang()
    if params:string("pset_slot"..i) == nil then -- if a pset that was assined to a pset_slot is deleted set the slot param to "none"
      params:set("pset_slot"..i, 1)
      save_slot_data()
    end
  end
  --print("updated params")
end

-- the pset name (string) needs to be converted back to the pset number for params:read(number)
-- the caveat is that you can't have multiple psets with the same name.
-- however, it brings the benefit that there is no pset number reference to the index of the pset_list
-- hence you can delete any pset in any order and you'll still load the correct pset.

-- an alternative would be to store the path of the pset (filename) together with the name in a table and read the filename params:read("filename")
function get_pset_number(name)
  local files_data = util.scandir(norns.state.data)
  for i = 1, #files_data do
    if files_data[i]:match("^.+(%..+)$") == ".pset" then
      local loaded_file = io.open(norns.state.data..files_data[i], "r")
      if loaded_file then
        io.input(loaded_file)
        local pset_id = string.sub(io.read(), 4, -1)
        if name == pset_id then
          local filename = norns.state.data..files_data[i]
          local pset_string = string.sub(filename, string.len(filename) - 6, -1)
          local number = pset_string:gsub(".pset", "")
          return util.round(number, 1) -- better to use tonumber?
        end
        io.close(loaded_file)
      end
    end
  end
end

-------- init --------

function init()

  -- build pset list before pset_slot params
  build_pset_list() 

  -- pset slot params
  params:add_group("pset_params", "pset slots", 1 + PSET_SLOTS)
  for i = 1, PSET_SLOTS do
    params:add_option("pset_slot"..i, "slot "..i, pset_list, 1)
    params:set_action("pset_slot"..i, function() gridredraw() end)
  end
  params:add_binary("save_pset_slots", ">> save slot settings", "trigger", 0)
  params:set_action("save_pset_slots", function() save_slot_data() end)

  params:bang()

  -- set pset_slots to saved settings
  load_slot_data()

  gridredraw()

  -- pset callbacks
  params.action_write = function(filename, name, number)
    -- your code
    --
    -- rebuild pset list and update param attributes
    clock.run(
      function()
        clock.sleep(0.5) -- haven't checked the timings. most probably is less is ok.
        build_pset_list()
        clock.sleep(0.5)
        update_slot_params()
      end
    )
    print("finished writing pset:'"..name.."'")
  end
  
  params.action_read = function(filename, silent, number)
    -- your code
    --
    -- set pset_slots to saved settings
    load_slot_data()    
  end
  
  params.action_delete = function(filename, name, number)
    -- your code
    --
    -- rebuild pset list and update param attributes
    clock.run(
      function()
        clock.sleep(0.5)
        build_pset_list()
        clock.sleep(0.5)
        update_slot_params()
      end
    )
    print("finished deleting pset:'"..name.."'")
  end
end


-------- grid UI --------

-- load psets via grid
function g.key(x, y, z)
  if z == 1 then
    if y == 8 and x <= PSET_SLOTS then -- need to adapt this to your use case. here PSET_SLOTS < 16
      local i = x
      if params:get("pset_slot"..i) ~= 1 then
        local pset_num = get_pset_number(params:string("pset_slot"..i))
        params:read(pset_num)
      end
    end
  end
  gridredraw()
end

function gridredraw()
  g:all(0)
  for i = 1, PSET_SLOTS do
    g:led(i, 8, params:get("pset_slot"..i) > 1 and 8 or 3)
  end
  g:refresh()
end


-------- cleanup --------

function cleanup()
  -- save pset_slots at cleanup in case one forgets to save
  save_slot_data()
end
