-- The playable edition is an explicit list. New catalog entries stay in reference
-- status until their rules are enabled. Neutral collections may be shared by ID.
return {
  {id="Fantasy", emblem="leaf", color={0.53,0.71,0.40},
   ink={0.13,0.23,0.16}, paper={0.74,0.78,0.59}, art="tabletop/assets/fantasy", featured=48,
   neutral={"Carnival"}, enabled={{1,70}}},
  {id="Water", emblem="wave", color={0.40,0.74,0.78},
   ink={0.09,0.23,0.26}, paper={0.65,0.79,0.77}, art="tabletop/assets/water", featured=43,
   neutral={"Carnival"}, enabled={{1,74}}},
  {id="Super", label="Comic", emblem="bolt", color={0.80,0.62,0.80},
   ink={0.24,0.17,0.29}, paper={0.78,0.70,0.78}, art="tabletop/assets/super", featured=66,
   neutral={"Carnival"}, enabled={{1,78}}},
  {id="Carnival", primary=false, emblem="cards", color={.83,.69,.41},
   ink={.25,.20,.14}, paper={.82,.75,.62}, enabled={}},
}
