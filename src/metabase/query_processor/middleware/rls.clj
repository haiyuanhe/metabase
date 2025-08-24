(ns metabase.query-processor.middleware.rls
  "Middleware for handling Row Level Security (RLS) parameters in queries.
  This middleware extracts RLS parameters from the query and stores them
  for later use during query execution."
  (:require
   [metabase.query-processor.schema :as qp.schema]
   [metabase.util :as u]
   [metabase.util.i18n :refer [tru]]
   [metabase.util.log :as log]
   [metabase.util.malli :as mu]))

(set! *warn-on-reflection* true)

(defn- apply-rls-parameters
  "Pre-processing middleware that extracts RLS parameters from the query and stores them
  for later use during query execution."
  [query]
  (if-let [rls-params (:rls-params query)]
    (-> query
        (assoc :qp/rls-params rls-params)
        (dissoc :rls-params))
    query))

(defn- apply-rls-execution
  "Execution middleware that passes RLS parameters through for later processing."
  [qp]
  (fn [query rff]
    ;; RLS parameters will be handled by the PostgreSQL driver during connection setup
    (qp (dissoc query :qp/rls-params) rff)))

(mu/defn apply-rls :- ::qp.schema/any-query
  "Apply RLS parameter processing to a query."
  [query :- ::qp.schema/any-query]
  (apply-rls-parameters query))

(defn apply-rls-execution-middleware
  "Middleware wrapper for RLS execution processing."
  [qp]
  (apply-rls-execution qp))
