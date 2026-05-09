from backend.nlp_classifier import NLPClassifier


def test(sentences):
    clf = NLPClassifier()
    for s in sentences:
        res = clf.classify(s, scenario="grease_fire")
        print("INPUT:", s)
        print("OUTPUT:", res["label"], "-", res["reason"])
        print()


if __name__ == "__main__":
    sentences = [
        "put water on it",
        "calm down, and call the BFP using 911 then get a towel and baking soda and put it over the fire to smother it and but do not use water",
        "calm down, and call the BFP using 911 then get a towel and baking soda and put it over the fire to smother it and put water on it",
        "don't use water; smother instead",
        "do not pour water on a grease fire",
        "smother it and avoid water",
        "smother it but don't use water",
    ]
    test(sentences)
