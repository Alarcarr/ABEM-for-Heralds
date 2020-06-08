import ftl;
import resources;

tidy class ColonizationEvent : Serializable {
	Object@ from;
	Object@ to;

	void write(Message& msg) {
		msg << from;
		msg << to;
	}

	void read(Message& msg) {
		msg >> from;
		msg >> to;
	}
};

tidy class DesignManager : Serializable {
dictionary[] designClasses;

	DesignManager() {
		designClasses.length = getEmpireCount();
	}

	uint getQueuedShips(string& name, int& revision, int& empireId) {
		DesignRevision@[] cls;
		if(designClasses.length <= uint(empireId)) designClasses.length = uint(empireId)+1;
		if(designClasses[empireId] is null) {
			designClasses[empireId] = dictionary();
			return 0;
		}
		if(!designClasses[empireId].exists(name))
			return 0;
		else designClasses[empireId].get(name, cls);
		if(int(cls.length) <= revision-1)
			return 0;
		if(cls[revision-1] is null)
			return 0;
		
		return cls[revision-1].queued + cls[revision-1].built;
	}

	uint getBuiltShips(const Design@ dsg) {
		return getBuiltShips(dsg.name, dsg.revision, dsg.owner.index);
	}

	uint getBuiltShips(string& name, int& revision, int& empireId) {
		DesignRevision@[] cls;
		if(designClasses.length <= uint(empireId)) designClasses.length = uint(empireId)+1;
		if(designClasses[empireId] is null) {
			designClasses[empireId] = dictionary();
			return 0;
		}
		if(!designClasses[empireId].exists(name))
			return 0;
		else designClasses[empireId].get(name, cls);
		if(int(cls.length) <= revision-1)
			return 0;
		if(cls[revision-1] is null)
			return 0;
		
		return cls[revision-1].built;
	}

	uint getActiveShips(const Design@ dsg) {
		return getActiveShips(dsg.name, dsg.revision, dsg.owner.index);
	}

	uint getActiveShips(string& name, int& revision, int& empireId) {
		DesignRevision@[] cls;
		if(designClasses.length <= uint(empireId)) designClasses.length = uint(empireId)+1;
		if(designClasses[empireId] is null) {
			designClasses[empireId] = dictionary();
			return 0;
		}
		if(!designClasses[empireId].exists(name))
			return 0;
		else designClasses[empireId].get(name, cls);
		if(int(cls.length) <= revision-1)
			return 0;
		if(cls[revision-1] is null)
			return 0;
		
		return cls[revision-1].ships.length;
	}

	DesignRevision@[] getClass(string key, uint index, uint8 empireId) {
		DesignRevision@[] cls;
		string[] keys = designClasses[empireId].getKeys();
		if(keys.length > index)
			designClasses[empireId].get(keys[index], cls);
		return cls;
	}

	void write(Message& msg) {
		msg << designClasses.length;
		for(uint8 i = 0, cnt = designClasses.length; i < cnt; ++i) {
			msg << designClasses[i].getSize();
			for(uint j = 0, jcnt = designClasses[i].getSize(); j < jcnt; ++j) {
				string key = designClasses[i].getKeys()[j];
				msg << key;
				DesignRevision@[] cls = getClass(key, j, i);
				msg << cls.length;
				for(uint k = 0, kcnt = cls.length; k < kcnt; ++k) {
					if(cls[k] is null)
						@cls[k] = DesignRevision();
					msg << cls[k];
				}
			}
		}
	}

	void read(Message& msg) {
		uint cnt = 0;
		msg >> cnt;
		designClasses.length = cnt;
		for(uint8 i = 0; i < cnt; ++i) {
			designClasses[i].deleteAll();
			uint jcnt = 0;
			msg >> jcnt;
			for(uint j = 0; j < jcnt; ++j) {
				string key;
				uint kcnt = 0;
				msg >> key;
				msg >> kcnt;
				DesignRevision@[] cls;
				for(uint k = 0; k < kcnt; ++k) {
					msg >> cls[k];
				}
				designClasses[i].set(key, cls);
			}
		}
	}
}

tidy class DesignRevision : Serializable {
	uint built;
	uint queued;
	Ship@[] ships;

	Ship@ get_ships(uint index) {
		return ships[index];
	}

	uint get_active() {
		return ships.length;
	}

	void write(Message& msg) {
		msg << built;
		msg << queued;
		msg << active;
		for(uint i = 0; i < active; ++i)
			msg << ships[i];
	}

	void read(Message& msg) {
		msg >> built;
		msg >> queued;
		uint cnt = 0;
		msg >> cnt;
		ships.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> ships[i];
	}
}

tidy class ObjectManager : Component_ObjectManager {
	ReadWriteMutex plMutex;
	Planet@[] planets;
	Asteroid@[] asteroids;
	Orbital@[] Orbitals;

	Mutex flingMutex;
	Object@[] flingBeacons;

	Mutex gateMutex;
	Object@[] gates;

	Mutex artifMutex;
	Artifact@[] artifacts;

	ReadWriteMutex designMutex;
	DesignManager@ designs;

	ColonizationEvent@[] colonizations;
	ColonizationEvent@[] queuedAutoColonizations;

	AutoImportDesc[] autoImports;

	ReadWriteMutex defenseMtx;
	array<Object@> defenseObjects;
	set_int defenseSet;

	double defenseRate = 0;
	double defenseStorage = 0;
	double defenseStored = 0;
	double localDefenseRate = 0;

	void getPlanets() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = planets.length; i < cnt; ++i)
			yield(planets[i]);
	}

	void getAutoImports() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = autoImports.length; i < cnt; ++i) {
			if(!autoImports[i].handled)
				yield(autoImports[i]);
		}
	}

	uint get_planetCount() {
		return planets.length;
	}

	Planet@ get_planetList(uint index) {
		ReadLock lock(plMutex);
		if(index >= planets.length)
			return null;
		return planets[index];
	}

	uint get_orbitalCount() {
		return Orbitals.length;
	}

	Orbital@ get_orbitals(uint index) {
		ReadLock lock(plMutex);
		if(index >= Orbitals.length)
			return null;
		return Orbitals[index];
	}

	Orbital@ getClosestOrbital(uint type, const vec3d& position) {
		ReadLock lock(plMutex);
		Orbital@ closest;
		double closestDist = INFINITY;
		for(uint i = 0, cnt = Orbitals.length; i < cnt; ++i) {
			Orbital@ orb = Orbitals[i];
			if(orb.hasModule(type)) {
				double d = orb.position.distanceToSQ(position);
				if(d < closestDist) {
					closestDist = d;
					@closest = orb;
				}
			}
		}
		return closest;
	}

	uint getQueuedShips(string name, int revision, Empire@ emp) {
		ReadLock lock(designMutex);
		return designs.getQueuedShips(name, revision, emp.index);
	}

	uint getBuiltShips(Empire& emp, Ship@ ship) {
		if(!ship.valid || ship.owner !is emp)
			return 0;

		ReadLock lock(designMutex);
		return designs.getBuiltShips(ship.blueprint.design);
	}

	uint getBuiltShips(string name, int revision, Empire@ emp) {
		ReadLock lock(designMutex);
		return designs.getBuiltShips(name, revision, emp.index);
	}

	uint getActiveShips(Empire& emp, Ship@ ship) {
		if(!ship.valid || ship.owner !is emp)
			return 0;
		
		ReadLock lock(designMutex);
		return designs.getActiveShips(ship.blueprint.design);
	}

	uint getActiveShips(string name, int revision, Empire@ emp) {
		ReadLock lock(designMutex);
		return designs.getActiveShips(name, revision, emp.index);
	}

	bool isFlingBeacon(Object@ obj) {
		Lock lock(flingMutex);
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i)
			if(flingBeacons[i] is obj)
				return true;
		return false;
	}

	void getAsteroids() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = asteroids.length; i < cnt; ++i)
			yield(asteroids[i]);
	}

	void getFlingBeacons() {
		Lock lock(flingMutex);
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i)
			yield(flingBeacons[i]);
	}

	void getStargates() {
		Lock lock(gateMutex);
		for(uint i = 0, cnt = gates.length; i < cnt; ++i)
			yield(gates[i]);
	}

	void getArtifacts() {
		Lock lock(artifMutex);
		for(uint i = 0, cnt = artifacts.length; i < cnt; ++i)
			yield(artifacts[i]);
	}

	void getOrbitals() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = Orbitals.length; i < cnt; ++i)
			yield(Orbitals[i]);
	}

	void getQueuedColonizations(Empire& emp) {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = queuedAutoColonizations.length; i < cnt; ++i) {
			auto@ q = queuedAutoColonizations[i];
			if(q.to.owner !is emp && q.from is null)
				yield(q.to);
		}
		for(uint i = 0, cnt = colonizations.length; i < cnt; ++i) {
			if(colonizations[i].to.owner !is emp)
				yield(colonizations[i].to);
		}
	}
	
	bool get_hasFlingBeacons() {
		return flingBeacons.length != 0;
	}

	Object@ getFlingBeacon(vec3d position) {
		Lock lock(flingMutex);
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i) {
			if(flingBeacons[i].position.distanceToSQ(position) < FLING_BEACON_RANGE_SQ)
				return flingBeacons[i];
		}
		return null;
	}

	Object@ getClosestFlingBeacon(vec3d position) {
		Lock lock(flingMutex);
		Object@ nearest;
		double dist = 0;
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i) {
			Object@ beacon = flingBeacons[i];
			double d = beacon.position.distanceToSQ(position);
			if(nearest is null || d < dist) {
				@nearest = beacon;
				dist = d;
			}
		}
		return nearest;
	}

	Object@ getClosestFlingBeacon(Object& obj) {
		Lock lock(flingMutex);
		Object@ nearest;
		double dist = 0;
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i) {
			Object@ beacon = flingBeacons[i];
			if(beacon is obj)
				continue;
			double d = beacon.position.distanceToSQ(obj.position);
			if(nearest is null || d < dist) {
				@nearest = beacon;
				dist = d;
			}
		}
		return nearest;
	}

	bool hasStargates(Empire& emp) {
		return hasStargates(emp, true);
	}

	bool hasStargates(Empire& emp, bool recursive) {
		bool result = gates.length != 0;
		if(result)
			return true;
		if(recursive) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(other is emp)
					continue;
				if((other.GateShareMask & emp.mask != 0) && (emp.GateShareMask & other.mask != 0) && other.hasStargates(false))
					return true;
			}
		}
		return result;
	}

	Object@ getStargate(Empire& emp, vec3d position) {
		return getStargate(emp, position, true);
	}

	Object@ getStargate(Empire& emp, vec3d position, bool recursive) {
		Object@ best;
		double bestDist = INFINITY;
		{
			Lock lock(gateMutex);
			for(uint i = 0, cnt = gates.length; i < cnt; ++i) {
				Object@ gate = gates[i];
				double d = gate.position.distanceToSQ(position);
				if(d < bestDist) {
					bestDist = d;
					@best = gate;
				}
			}
		}
		if(recursive) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(other is emp || !other.major)
					continue;
				if((other.GateShareMask & emp.mask == 0) || (emp.GateShareMask & other.mask == 0) || !other.hasStargates(false))
					continue;
				// This is a terribly, TERRIBLY dangerous idea. Kids, do not try this at home. Or anywhere.
				Object@ allyGate = other.getStargate(position, false);
				double d = allyGate.position.distanceToSQ(position);
				if(d < bestDist) {
					bestDist = d;
					@best = allyGate;
				}
			}
		}		
		return best;
	}

	bool isDefending(Object@ obj) {
		if(obj is null)
			return false;
		ReadLock lck(defenseMtx);
		return defenseSet.contains(obj.id);
	}

	bool get_hasDefending() {
		return defenseObjects.length > 0;
	}

	void getDefending() {
		ReadLock lck(defenseMtx);
		for(uint i = 0, cnt = defenseObjects.length; i < cnt; ++i)
			yield(defenseObjects[i]);
	}

	void setDefending(Object@ obj, bool value) {
		if(obj is null)
			return;
		WriteLock lck(defenseMtx);
		if(value) {
			if(defenseSet.contains(obj.id))
				return;

			defenseSet.insert(obj.id);
			defenseObjects.insertLast(obj);
		}
		else {
			if(!defenseSet.contains(obj.id))
				return;

			defenseSet.erase(obj.id);
			defenseObjects.remove(obj);
		}
	}

	double get_globalDefenseRate() {
		return defenseRate + localDefenseRate;
	}

	double get_globalDefenseStorage() {
		return defenseStorage;
	}

	double get_globalDefenseStored() {
		return defenseStored;
	}

	void readObjects(Message& msg) {
		WriteLock wlock(plMutex);

		if(msg.readBit()) {
			msg >> defenseRate;
			msg >> localDefenseRate;
			msg >> defenseStorage;
			msg >> defenseStored;
		}

		if(msg.readBit()) {
			uint cnt = 0;
			msg >> cnt;
			planets.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> planets[i];

			msg >> cnt;
			asteroids.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> asteroids[i];

			msg >> cnt;
			Orbitals.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> Orbitals[i];

			{
				Lock lock(flingMutex);
				msg >> cnt;
				flingBeacons.length = cnt;
				for(uint i = 0; i < cnt; ++i)
					msg >> flingBeacons[i];
			}

			{
				Lock lock(gateMutex);
				msg >> cnt;
				gates.length = cnt;
				for(uint i = 0; i < cnt; ++i)
					msg >> gates[i];
			}

			{
				Lock lock(artifMutex);
				msg >> cnt;
				artifacts.length = cnt;
				for(uint i = 0; i < cnt; ++i)
					msg >> artifacts[i];
			}

			{
				ReadLock lock(defenseMtx);
				msg >> cnt;
				defenseObjects.length = cnt;
				defenseSet.clear();
				for(uint i = 0; i < cnt; ++i) {
					msg >> defenseObjects[i];
					if(defenseObjects[i] !is null)
						defenseSet.insert(defenseObjects[i].id);
				}
			}
		}

		if(msg.readBit()) {
			uint cnt = 0;
			msg >> cnt;
			colonizations.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				if(colonizations[i] is null)
					@colonizations[i] = ColonizationEvent();
				msg >> colonizations[i];
			}

			msg >> cnt;
			queuedAutoColonizations.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				if(queuedAutoColonizations[i] is null)
					@queuedAutoColonizations[i] = ColonizationEvent();
				msg >> queuedAutoColonizations[i];
			}
		}

		if(msg.readBit()) {
			uint cnt = 0;
			msg >> cnt;
			autoImports.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> autoImports[i];
		}

		if(msg.readBit()) {
			msg >> designs;
		}
	}
};
