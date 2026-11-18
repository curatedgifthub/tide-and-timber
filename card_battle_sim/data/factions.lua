-- The playable edition is an explicit list. New catalog entries stay in reference
-- status until their rules are enabled. Neutral collections may be shared by ID.
return {
  {id="Fantasy", label="Timber", emblem="leaf", color={0.53,0.71,0.40},
   ink={0.13,0.23,0.16}, paper={0.74,0.78,0.59}, art="tabletop/assets/fantasy", featured=48,
   starter30={48,1,4,6,31,10,11,15,17,21,25,28,32,36,41,42,44,51,54,65,2,9,16,23,27,29,24,35,45,52},
   starter={48,1,4,6,31,10,11,15,17,21,25,28,32,36,41,42,44,51,54,65,12,13,16,23,27,29,37,43,55,64},
   neutral={"Carnival"}, enabled={{1,70}}},
  {id="Water", label="Tide", emblem="wave", color={0.40,0.74,0.78},
   ink={0.09,0.23,0.26}, paper={0.65,0.79,0.77}, art="tabletop/assets/water", featured=43,
   starter30={43,2,4,6,8,10,16,17,19,21,25,26,27,32,38,41,49,53,57,63,9,22,23,45,50,56,61,62,64,65},
   starter={43,2,4,6,8,10,16,17,19,21,25,26,27,32,38,41,49,53,57,63,1,7,9,22,30,45,50,55,62,65},
   neutral={"Carnival"}, enabled={{1,74}}},
  {id="Super", label="Comic", starter30={66,61,15,27,32,57,71,72,73,74,75,78,2,11,20,21,62,8,12,14,24,30,47,49,51,61,57,15,27,30}, starter={66,61,15,27,32,57,71,72,73,74,75,76,77,78,2,3,11,20,21,62}, numerical_chains=false, emblem="bolt", color={0.80,0.62,0.80},
   ink={0.24,0.17,0.29}, paper={0.78,0.70,0.78}, art="tabletop/assets/super", featured=66,
   neutral={"Carnival"}, enabled={{1,78}}},
  {id="Carnival", primary=false, emblem="cards", color={.83,.69,.41},
   ink={.25,.20,.14}, paper={.82,.75,.62}, enabled={}},
}
