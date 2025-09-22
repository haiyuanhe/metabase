(ns metabase.rls.context
  (:require
   [clojure.string :as str]
   [metabase.util.log :as log]))

(def ^:dynamic *rls-context*
  "Request/thread-scoped RLS parameters map. Expected keys like :rls_user_id, :rls_company_id, etc."
  nil)

(def ^:private allowed-key-prefix "rls_")

(defn- allowed-key? [k]
  (when k
    (str/starts-with? (name k) allowed-key-prefix)))

(defn sanitize-rls-value [value]
  (when (some? value)
    (-> (str value)
        (str/replace #"[^a-zA-Z0-9_\-@.]" "")
        (str/trim))))

(defn validate-rls-params [params]
  (when (map? params)
    (let [rls-params (into {}
                            (keep (fn [[k v]]
                                    (when (allowed-key? k)
                                      (let [sv (sanitize-rls-value v)]
                                        (when (and sv (<= (count sv) 100))
                                          [k sv])))))
                            params)]
      (when (> (count rls-params) 0)
        rls-params))))

(defn strip-rls-params
  "Remove any params whose key starts with rls_."
  [params]
  (if (map? params)
    (into {}
          (remove (fn [[k _]] (allowed-key? k)))
          params)
    params))

(defn get []
  *rls-context*)

(defn has? []
  (boolean (seq *rls-context*)))

(defn context->setup-sql
  "Translate sanitized RLS params into a vector of SET LOCAL statements. Role is auto-set to 'authenticated'."
  [rls-params]
  (when (seq rls-params)
    (let [kv->sql (fn [[k v]]
                    (let [guc-name (-> (name k)
                                        (str/replace "rls_" "metabase.rls.")
                                        (str/replace #"[^a-zA-Z0-9_.]" ""))]
                      (format "SET LOCAL %s = '%s';" guc-name v)))]
      (into [(format "SET LOCAL role = 'authenticated';")] (map kv->sql rls-params)))))
