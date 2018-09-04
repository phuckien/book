// tag::count[]
MATCH (category:Category {name: "Hotels"})
RETURN size((category)<-[:IN_CATEGORY]-()) AS businesses,
       size((:Review)-[:REVIEWS]->(:Business)-[:IN_CATEGORY]->(category)) AS reviews
// end::count[]

// tag::top-rated[]
MATCH (review:Review)-[:REVIEWS]->(business:Business),
      (business)-[:IN_CATEGORY]->(:Category {name:"Hotels"}),
      (business)-[:IN_CITY]->(:City {name: "Las Vegas"})
WITH business, count(*) AS reviews, avg(review.stars) AS averageRating
ORDER BY reviews DESC
LIMIT 10
RETURN business.name AS business,
       reviews,
       averageRating
// end::top-rated[]

// tag::best-reviewers[]
CALL algo.pageRank(
  'MATCH (u:User)-[:WROTE]->()-[:REVIEWS]->()-[:IN_CATEGORY]->(:Category {name: $category})
   WITH u, count(*) AS reviews
   WHERE reviews > $cutOff
   RETURN id(u) AS id',
  'MATCH (u1:User)-[:WROTE]->()-[:REVIEWS]->()-[:IN_CATEGORY]->(:Category {name: $category})
   MATCH (u1)-[:FRIENDS]->(u2)
   RETURN id(u1) AS source, id(u2) AS target',
  {graph: "cypher", write: true, writeProperty: "hotelPageRank",
   params: {category: "Hotels", cutOff: 3}}
)
// end::best-reviewers[]

// tag::best-reviewers-query[]
MATCH (u:User)
WHERE u.hotelPageRank > 0
WITH u
ORDER BY u.hotelPageRank DESC
LIMIT 10
RETURN u.name AS name,
       u.hotelPageRank AS pageRank,
       size((u)-[:WROTE]->()-[:REVIEWS]->()-[:IN_CATEGORY]->
            (:Category {name: "Hotels"})) AS hotelReviews,
       size((u)-[:WROTE]->()) AS totalReviews,
       size((u)-[:FRIENDS]-()) AS friends
// end::best-reviewers-query[]

// tag::bellagio[]
MATCH (b:Business {name: "Bellagio Hotel"})
MATCH (b)<-[:REVIEWS]-(review)<-[:WROTE]-(user)
WHERE exists(user.hotelPageRank)
RETURN user.name AS name,
       user.hotelPageRank AS pageRank,
       review.stars AS stars
ORDER BY user.hotelPageRank DESC
LIMIT 10
// end::bellagio[]

// tag::bellagio-bad-rating[]
MATCH (b:Business {name: "Bellagio Hotel"})
MATCH (b)<-[:REVIEWS]-(review)<-[:WROTE]-(user)
WHERE exists(user.hotelPageRank) AND review.stars < 4
RETURN user.name AS name,
       user.hotelPageRank AS pageRank,
       review.stars AS stars
ORDER BY user.hotelPageRank DESC
LIMIT 10
// end::bellagio-bad-rating[]

// tag::bellagio-bw-tagging[]
MATCH (u:User)-[:WROTE]->()-[:REVIEWS]->()-[:IN_CITY]->(:City {name: "Las Vegas"})
WITH distinct u AS u
SET u:LasVegas
// end::bellagio-bw-tagging[]


// tag::bellagio-bw[]
CALL algo.betweenness.sampled('LasVegas', 'FRIENDS',
  {write: true, writeProperty: "between", maxDepth: 4, probability: 0.2}
)
// end::bellagio-bw[]

// tag::bellagio-bw-query[]
MATCH(u:User)-[:WROTE]->()-[:REVIEWS]->(:Business {name:"Bellagio Hotel"})
WHERE exists(u.between)
RETURN u.name AS user,
       toInteger(u.between) AS betweenness,
       u.hotelPageRank AS pageRank,
       size((u)-[:WROTE]->()-[:REVIEWS]->()-[:IN_CATEGORY]->(:Category {name: "Hotels"}))
       AS hotelReviews
ORDER BY u.between DESC
LIMIT 10
// end::bellagio-bw-query[]

// tag::bellagio-restaurants[]
MATCH (u:User)-[:WROTE]->()-[:REVIEWS]->(:Business {name:"Bellagio Hotel"})
WHERE exists(u.between)
WITH u
ORDER BY u.between DESC
LIMIT 50
MATCH (u)-[:WROTE]->(review)-[:REVIEWS]-(business),
      (business)-[:IN_CATEGORY]->(cat:Category {name: "Restaurants"}),
      (business)-[:IN_CITY]->(:City {name: "Las Vegas"})
WITH business, avg(review.stars) AS averageReview, count(*) AS numberOfReviews
WHERE numberOfReviews >= 3
RETURN business.name, averageReview, numberOfReviews
ORDER BY averageReview DESC
LIMIT 10
// end::bellagio-restaurants[]



// tag::category-hierarchies[]
CALL algo.labelPropagation.stream(
  'MATCH (c:Category) RETURN id(c) AS id',
  'MATCH (c1:Category)<-[:IN_CATEGORY]-()-[:IN_CATEGORY]->(c2:Category)
   WHERE id(c1) < id(c2)
   RETURN id(c1) AS source, id(c2) AS target, count(*) AS weight',
  {graph: "cypher"}
)
YIELD nodeId, label
MATCH (c:Category) WHERE id(c) = nodeId
MERGE (sc:SuperCategory {name: "SuperCategory-" + label})
MERGE (c)-[:IN_SUPER_CATEGORY]->(sc)
// end::category-hierarchies[]

// tag::category-friendly-name[]
MATCH (sc:SuperCategory)<-[:IN_SUPER_CATEGORY]-(category)
WITH sc, category, size((category)<-[:IN_CATEGORY]-()) as size
ORDER BY size DESC
WITH sc, collect(category.name)[0] as biggestCategory
ORDER BY size((sc)<-[:IN_SUPER_CATEGORY]-()) DESC
SET sc.friendlyName = "SuperCat-" + biggestCategory
// end::category-friendly-name[]


// tag::similar-categories[]
MATCH (hotels:Category {name: "Hotels"}),
      (hotels)-[:IN_SUPER_CATEGORY]->()<-[:IN_SUPER_CATEGORY]-(otherCategory)
RETURN otherCategory.name AS otherCategory,
       size((otherCategory)<-[:IN_CATEGORY]-()) AS businesses
ORDER BY businesses DESC
LIMIT 10
// end::similar-categories[]


// tag::similar-categories-vegas[]
MATCH (hotels:Category {name: "Hotels"}),
      (lasVegas:City {name: "Las Vegas"}),
      (hotels)-[:IN_SUPER_CATEGORY]->()<-[:IN_SUPER_CATEGORY]-(otherCategory)
RETURN otherCategory.name AS otherCategory,
       size((otherCategory)<-[:IN_CATEGORY]-()-[:IN_CITY]->(lasVegas)) AS count
ORDER BY count DESC
LIMIT 10
// end::similar-categories-vegas[]

// tag::trip-plan[]
MATCH (hotels:Category {name: "Hotels"}),
      (hotels)-[:IN_SUPER_CATEGORY]->()<-[:IN_SUPER_CATEGORY]-(otherCategory),
      (otherCategory)<-[:IN_CATEGORY]-(business)
WHERE (business)-[:IN_CITY]->(:City {name: "Las Vegas"})
WITH otherCategory, count(*) AS count,
     collect(business) AS businesses,
     apoc.coll.avg(collect(business.averageStars)) AS categoryAverageStars
ORDER BY rand() DESC
LIMIT 10
WITH otherCategory,
     [b in businesses where b.averageStars >= categoryAverageStars] AS businesses
RETURN otherCategory.name AS otherCategory,
       [b in businesses | b.name][toInteger(rand() * size(businesses))] AS business
// end::trip-plan[]
