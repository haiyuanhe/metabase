(ns metabase.query-processor.middleware.rls
  "RLS context and SQL setup helpers. See metabase_rls_solution.md."
  (:require
   [clojure.string :as str]
   [metabase.util.log :as log]))

(def ^:dynamic *rls-context* nil)

(defn sanitize-rls-value [value]
  (when value
    (-> (str value)
        (str/replace #"[^a-zA-Z0-9_\-@.]" "")
        (str/trim))))

(defn- clean-params [params]
  (into {}
        (for [[k v] params
              :let [sv (sanitize-rls-value v)]
              :when (some? sv)]
          [k sv])))

(defn set-rls-context! [params]
  (let [clean (clean-params params)]
    (when (seq clean)
      (log/info "RLS: Setting context for request" clean))
    (set! *rls-context* clean)))

(defn get-rls-context [] *rls-context*)

(defn clear-rls-context! []
  (when *rls-context*
    (log/debug "RLS: Context cleared for thread"))
  (set! *rls-context* nil))

(defn wrap-rls-context [qp]
  (fn [query]
    ;; passthrough; context should already be bound per-request in API layer
    (qp query)))

(defn wrap-sql-with-rls
  "Build setup SQL statements for current RLS context. Returns vector of SET LOCAL statements.
   Role is auto-set to 'authenticated' when context present."
  [^clojure.lang.IPersistentMap rls]
  (when (seq rls)
    (let [clean        (into {} (for [[k v] rls] [(keyword (name k)) v]))
          rls-key->var (fn [k]
                         (let [n (name k)]
                           (if (str/starts-with? n "rls_")
                             (subs n 4)
                             n)))
          var-pairs    (for [[k v] clean]
                         [(rls-key->var k) v])
          statements   (into ["SET LOCAL role = 'authenticated';"]
                             (for [[var v] var-pairs]
                               (format "SET LOCAL metabase.rls.%s = '%s';" var v)))]
      (log/info "RLS: Preparing SET LOCAL statements" {:context clean :statements statements})
      statements)))


