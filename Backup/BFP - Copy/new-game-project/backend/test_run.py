from backend.nlp_classifier import NLPClassifier
import json

clf = NLPClassifier()
with open("g:/Code/BFP/new-game-project/backend/test_run_out.txt", "w", encoding="utf-8") as out:
	out.write("normalized: " + clf._normalize("Put it out with water") + "\n")
	res = clf.classify("Put it out with water", "grease_fire")
	out.write(str(res) + "\n")
	out.write(json.dumps(res, ensure_ascii=False, indent=2) + "\n")

	res2 = clf.classify("Smother it", "grease_fire")
	out.write(json.dumps(res2, ensure_ascii=False, indent=2) + "\n")
