# Matter Simulation: Component Archetype Dictionary

This document serves as a blueprint for constructing physical entities using an Entity-Component-System (ECS). By mixing and matching these component values, the solver systems will naturally simulate complex emergent physics without hardcoded interactions.

---

## 1. Metals & Minerals (The Unyielding)

### High-Carbon Steel (Weapon/Armor Grade)
*   **Physical:** State: `Solid` | Density: `7,850 kg/m³`
*   **Mechanical:** Hardness: `6.5` | Yield: `850 MPa` | Elasticity: `0.3` (Bends slightly under extreme force)
*   **Thermodynamics:** Melting: `1,500°C` | Conductivity: `45.0` | Ignition: `None`
*   **Chemical/Organic:** *None*

### Obsidian (Volcanic Glass)
*   **Physical:** State: `Solid` | Density: `2,500 kg/m³`
*   **Mechanical:** Hardness: `5.5` | Yield: `40 MPa` | Elasticity: `0.01` (Extremely brittle, shatters into sharp fragments)
*   **Thermodynamics:** Melting: `1,000°C` | Conductivity: `1.2` (Insulator)
*   **Chemical/Organic:** *None*

### Silica Aerogel (Extreme Insulator)
*   **Physical:** State: `Solid` | Density: `1.5 kg/m³` (Barely heavier than air)
*   **Mechanical:** Hardness: `1.0` | Yield: `0.1 MPa` (Crushes instantly if stepped on)
*   **Thermodynamics:** Melting: `1,200°C` | Conductivity: `0.01` (Perfect thermal shield)
*   **Chemical/Organic:** *None*

---

## 2. Botanicals & Biologicals (The Decaying)

### Dry Tumbleweed / Kindling
*   **Physical:** State: `Solid` | Density: `50 kg/m³` (High volume, low mass)
*   **Mechanical:** Hardness: `1.0` | Yield: `5 MPa` | Elasticity: `0.5`
*   **Thermodynamics:** Melting: `None` | Conductivity: `0.1` | Ignition: `150°C`
*   **Organic:** Moisture: `0.05` (Bone dry) | Nutrition: `5` | Rot_Rate: `Fast`
*   **Chemical:** Flammability: `Very High` (Burns fast and hot)

### Raw Ogre Meat
*   **Physical:** State: `Solid` | Density: `1,050 kg/m³`
*   **Mechanical:** Hardness: `1.5` | Yield: `10 MPa` | Elasticity: `0.8` (Fleshy, bounces back)
*   **Thermodynamics:** Melting: `None` | Ignition: `None` (Too wet to ignite directly)
*   **Organic:** Moisture: `0.75` | Nutrition: `500` | Rot_Rate: `Moderate` | Toxicity: `Mild` (Eaten raw)

### Giant Spider Silk
*   **Physical:** State: `Solid` | Density: `1,300 kg/m³`
*   **Mechanical:** Hardness: `2.0` | Yield: `1,100 MPa` (Stronger than steel per weight) | Elasticity: `0.9` (Stretches massively before snapping)
*   **Rheological:** Adhesion: `High` (Traps moving entities)
*   **Organic:** Moisture: `0.1` | Rot_Rate: `Extremely Slow`

---

## 3. Liquids & Fluids (The Flowing)

### Pure Water (The Baseline)
*   **Physical:** State: `Liquid` | Density: `1,000 kg/m³`
*   **Thermodynamics:** Melting: `0°C` | Boiling: `100°C` | Specific_Heat: `4,184 J/kg` (Takes massive energy to boil)
*   **Rheological:** Viscosity: `1.0` | Adhesion: `Low` | Non_Newtonian: `0.0`
*   **Chemical:** Acidity_pH: `7.0` (Neutral) | Corrosiveness: `0.0` | Flammability: `0.0`

### Greek Fire / Napalm
*   **Physical:** State: `Liquid` | Density: `800 kg/m³` (Floats on water)
*   **Thermodynamics:** Boiling: `300°C` | Ignition: `40°C`
*   **Rheological:** Viscosity: `500.0` (Thick syrup) | Adhesion: `Extreme` (Sticks to targets, impossible to shake off)
*   **Chemical:** Flammability: `Extreme` (Burns aggressively for a long time)

### Oobleck Trap (Non-Newtonian Fluid)
*   **Physical:** State: `Liquid` | Density: `1,100 kg/m³`
*   **Rheological:** Viscosity: `10.0` | Adhesion: `Moderate` | Non_Newtonian: `0.95` (Walk slowly and you sink; sprint across and it acts like concrete)

---

## 4. Gases & Vapors (The Ephemeral)

### Cave Methane
*   **Physical:** State: `Gas` | Density: `0.65 kg/m³` (Rises to the ceiling)
*   **Thermodynamics:** Ignition: `500°C`
*   **Rheological:** Viscosity: `0.01`
*   **Chemical:** Flammability: `Extreme` (Generates explosion entity upon ignition)
*   **Organic:** Toxicity: `Moderate` (Suffocates breathing entities)

### Chlorine / Poison Cloud
*   **Physical:** State: `Gas` | Density: `3.2 kg/m³` (Heavy, sinks to the floor and fills trenches)
*   **Thermodynamics:** Ignition: `None`
*   **Chemical:** Acidity_pH: `2.0` (Highly acidic) | Corrosiveness: `High` (Eats away at metal armor slowly)
*   **Organic:** Toxicity: `Extreme` (Rapid damage to biologicals)

---

## 5. Exotic & Magical (The Bizarre)

### Volatile Icosidodecahedron (Strained Carbon)
*   **Physical:** State: `Solid` | Density: `3,500 kg/m³`
*   **Mechanical:** Hardness: `9.0` | Yield: `10 MPa` | Elasticity: `0.0` (Cannot bend, shatters into explosive force upon localized impact)
*   **Thermodynamics:** Melting: `None` | Ignition: `80°C` (Thermal glass cannon; violently destabilizes when heated)

### Ectoplasm (Ghost Residue)
*   **Physical:** State: `Colloid` | Density: `0.1 kg/m³` (Lighter than air)
*   **Thermodynamics:** Specific_Heat: `-500` (Magical property: Endothermic. Drains heat from the room, freezing nearby water)
*   **Rheological:** Viscosity: `50.0` | Adhesion: `High`
*   **Organic:** Rot_Rate: `Evaporates over time` | Toxicity: `Spiritual Damage`