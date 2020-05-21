local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

-- Replaces its entity with a flood-filled patch of terrain.
local TerrainPatchComponent = require 'stonehearth.components.terrain_patch.terrain_patch_component'
local AceTerrainPatchComponent = class()

local log = radiant.log.create_logger('terrain_patch_component')

function AceTerrainPatchComponent:initialize()
   self._sv._current_index = nil
   self._sv._max_index = nil
   self._sv._terrain_tag = nil
   self._sv._interval = nil
end

AceTerrainPatchComponent._ace_old_activate = TerrainPatchComponent.activate
function AceTerrainPatchComponent:activate()
   -- this is actually harder than I thought; the idea was to mimic natural terrain types/colors based on elevation
   -- but that's calculated in a rather complex process during world generation and not saved
   -- local json = radiant.entities.get_json(self) or {}
   -- if json.match_biome_tags then
   --    self._match_biome_tags = true
   -- end
   
   self:_ace_old_activate()

   if self._sv._current_index then
      self:_start_placement()
   end
end

AceTerrainPatchComponent._ace_old__start_placement = TerrainPatchComponent._start_placement
function AceTerrainPatchComponent:_start_placement()
   self:_ace_old__start_placement()
   self:_ensure_water_obstruction()
end

function AceTerrainPatchComponent:_get_terrain_tag(location)
   -- if self._match_biome_tags then
   --    if not self._biome then
   --       self._biome = stonehearth.world_generation:get_biome_generation_data()
   --    end

   --    if self._biome then
   --       return self._biome:get_terrain_code(location.y)
   --    end
   -- end

   return self._sv._terrain_tag
end

function AceTerrainPatchComponent:_location_to_cube(location)
   local tag = self:_get_terrain_tag(location)
   return Cube3(Point3(location.x - 1, location.y,     location.z - 1),
                Point3(location.x,     location.y + 1, location.z),
                tag)
end

function AceTerrainPatchComponent:_advance_to_next_location()
   local location
   repeat
      local offset = self:_location_in_spiral(self._sv._current_index)
      self._sv._current_index = self._sv._current_index + 1
      location = self:_get_origin() + Point3(offset[1], 0, offset[2])
      
      local entities_in_cube = radiant.terrain.get_entities_in_cube(self:_location_to_cube(location))
      for _, entity in pairs(entities_in_cube) do
         if entity:get_id() == self._entity:get_id() then
            -- it's our reserved collision region
            break
         end

         if entity:get('terrain') then
            location = nil
            break
         end

         local rcs = entity:get_component('region_collision_shape')
         if rcs and rcs:get_region_collision_type() ~= _radiant.om.RegionCollisionShape.NONE then
            location = nil
            break
         end

         local designation = radiant.entities.get_entity_data(entity, 'stonehearth:designation')
         if designation and not designation.allow_placed_items then
            location = nil
            break
         end
      end
   until location or self._sv._current_index >= self._sv._max_index

   return location
end

AceTerrainPatchComponent._ace_old__place_block = TerrainPatchComponent._place_block
function AceTerrainPatchComponent:_place_block(location)
   -- remove the collision region for this point
   local rcs = self._entity:get_component('region_collision_shape')
   if rcs then
      local offset = location - self:_get_origin()
      local region = rcs:get_region()
      --log:debug('removing %s from region_collision_shape (%s: %s)', offset, region:get(), region:get():get_bounds())
      region:modify(function(cursor)
            cursor:subtract_point(offset)
         end)
   else
      log:debug('no region_collision_shape component!')
   end

   self:_ace_old__place_block(location)
end

function AceTerrainPatchComponent:_ensure_water_obstruction()
   local region = Region3()
   local index = self._sv._current_index
   local max_index = self._sv._max_index
   local origin = self:_get_origin()

   while index < max_index do
      local location_offset
      local location

      repeat
         local offset = self:_location_in_spiral(index)
         index = index + 1
         location_offset = Point3(offset[1], 0, offset[2])
         location = location_offset + origin
         
         local entities_in_cube = radiant.terrain.get_entities_in_cube(self:_location_to_cube(location))
         for _, entity in pairs(entities_in_cube) do
            if entity:get('terrain') then
               location = nil
               break
            end

            local rcs = entity:get_component('region_collision_shape')
            if rcs and rcs:get_region_collision_type() ~= _radiant.om.RegionCollisionShape.NONE then
               location = nil
               break
            end

            local designation = radiant.entities.get_entity_data(entity, 'stonehearth:designation')
            if designation and not designation.allow_placed_items then
               location = nil
               break
            end
         end
      until location or index >= max_index

      if location then
         region:add_point(location_offset)
      end
   end

   if not region:empty() then
      --log:debug('setting region_collision_shape to %s (%s) at %s', region, region:get_bounds(), origin)
      local rcs = self._entity:add_component('region_collision_shape')
      rcs:set_region_collision_type(_radiant.om.RegionCollisionShape.SOLID)
         :set_region(_radiant.sim.alloc_region3())
         :get_region():modify(function(cursor)
               cursor:copy_region(region)
            end)
   end
end

return AceTerrainPatchComponent
