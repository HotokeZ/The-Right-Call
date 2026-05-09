"""Custom pure-Python TF-IDF and Cosine Similarity Classifier.

Because we do not want external dependencies like scikit-learn, this class
builds a mathematical Bag-of-Words and calculates Term Frequency-Inverse 
Document Frequency (TF-IDF) vectors from the 600-scenario dataset. It then
compares player input against known 'safe' and 'unsafe' documents to score 
the response contextually.
"""
import json
import os
import math
import re
from typing import Dict, List, Optional, Any

try:
    from backend.tagalog_utils import normalize_taglish, get_tagalog_negations
except ImportError:
    # Fallback
    def normalize_taglish(text: str) -> str: return text
    def get_tagalog_negations() -> set: return set()


DEFAULT_BANK = os.path.join(os.path.dirname(__file__), "scenarios_bank.json")

class NLPClassifier:
    def __init__(self, bank_path: Optional[str] = None):
        self.bank_path = bank_path or DEFAULT_BANK
        self.vocab = {}
        self.idf_cache = {}
        self.trained_documents = [] # list of dicts: {'text': str, 'label': str, 'scenario': str, 'vec': dict}
        
        self.total_docs = 0
        self._train_from_bank()

    def _tokenize(self, text: str) -> List[str]:
        text = text.lower()
        text = normalize_taglish(text)
        # remove punctuation
        text = re.sub(r'[^a-z0-9\s_]', '', text)
        words = text.split()
        return [w for w in words if w]

    def _train_from_bank(self):
        """Build the vocabulary and document corpus from the JSON dataset."""
        if not os.path.exists(self.bank_path):
            return
            
        with open(self.bank_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            scenarios = data.get("scenarios", [])
            
        # We will treat each keyword and option explanation as a training "document"
        raw_documents = []
        for s in scenarios:
            cat = s.get("type", "unknown")
            
            # Learn from keywords
            for word in s.get("safe_keywords", []):
                raw_documents.append({"text": word, "label": "safe", "scenario": cat})
            for word in s.get("unsafe_keywords", []):
                raw_documents.append({"text": word, "label": "unsafe", "scenario": cat})
                
            # Learn from multiple choice descriptions (they contain deep semantic meaning)
            for opt in s.get("options", []):
                raw_documents.append({
                    "text": opt.get("text", "") + " " + opt.get("explanation", ""),
                    "label": opt.get("label", "uncertain"),
                    "scenario": cat
                })
        
        # Calculate overall word frequencies (DF)
        df_counts = {}
        self.total_docs = len(raw_documents)
        
        for doc in raw_documents:
            tokens = set(self._tokenize(doc["text"]))
            for t in tokens:
                df_counts[t] = df_counts.get(t, 0) + 1
                
        # Calculate IDF values
        for word, count in df_counts.items():
            self.idf_cache[word] = math.log(self.total_docs / (1.0 + count))
            
        # Convert all training documents to TF-IDF vectors
        for doc in raw_documents:
            vec = self._vectorize(doc["text"])
            self.trained_documents.append({
                "label": doc["label"],
                "scenario": doc["scenario"],
                "vec": vec
            })

    def _vectorize(self, text: str) -> Dict[str, float]:
        tokens = self._tokenize(text)
        if not tokens:
            return {}
            
        # Term Frequency
        tf = {}
        for t in tokens:
            tf[t] = tf.get(t, 0.0) + 1.0
            
        # Normalize by length and multiply by IDF
        vec = {}
        length = len(tokens)
        for t, freq in tf.items():
            val_tf = freq / length
            val_idf = self.idf_cache.get(t, math.log(self.total_docs / 1.0)) # unseen word penalization
            vec[t] = val_tf * val_idf
            
        return vec

    def _cosine_similarity(self, vecA: Dict[str, float], vecB: Dict[str, float]) -> float:
        intersection = set(vecA.keys()) & set(vecB.keys())
        dot_product = sum([vecA[x] * vecB[x] for x in intersection])
        
        sumA = sum([val**2 for val in vecA.values()])
        sumB = sum([val**2 for val in vecB.values()])
        
        if sumA == 0 or sumB == 0:
            return 0.0
            
        return dot_product / (math.sqrt(sumA) * math.sqrt(sumB))

    def classify(self, text: str, scenario_type: str) -> Dict[str, Any]:
        """Classify a response by comparing its TF-IDF vector against the dataset."""
        input_vec = self._vectorize(text)
        if not input_vec:
            return {
                "label": "uncertain",
                "reason": "I did not understand your message."
            }

        # Check for negations mathematically (simple heuristic: if flip words exist)
        tokens = set(self._tokenize(text))
        negations = {"no", "not", "dont", "do not", "never", "stop", "cancel"} | get_tagalog_negations()
        has_negation = len(tokens & negations) > 0
        
        # Find best matching document in our trained database for this specific scenario
        best_safe_score = 0.0
        best_unsafe_score = 0.0
        
        # Filter training corpus to relevant items to speed up processing
        # and keep context accurate.
        corpus = [d for d in self.trained_documents if d["scenario"] == scenario_type]
        if not corpus:
            corpus = self.trained_documents # fallback to entire dataset
            
        for doc in corpus:
            sim = self._cosine_similarity(input_vec, doc["vec"])
            if doc["label"] == "safe" and sim > best_safe_score:
                best_safe_score = sim
            elif doc["label"] == "unsafe" and sim > best_unsafe_score:
                best_unsafe_score = sim

        # Resolve classification
        label = "uncertain"
        reason = "Partially understood, but consider safer instructions."
        
        if best_safe_score > 0.1 and best_safe_score > best_unsafe_score:
            label = "safe"
            reason = "Your instruction strongly aligns with safe standard procedures."
            if has_negation:
                label = "unsafe"
                reason = "Your instruction negated a safe standard procedure. This is risky."
        elif best_unsafe_score > 0.1 and best_unsafe_score >= best_safe_score:
            label = "unsafe"
            reason = "Your instruction strongly aligns with unsafe, highly dangerous actions!"
            if has_negation:
                label = "safe"
                reason = "You correctly prevented a highly dangerous typical mistake."

        return {
            "label": label,
            "reason": reason,
            "similarity_scores": {
                "safe_match": best_safe_score,
                "unsafe_match": best_unsafe_score
            }
        }
