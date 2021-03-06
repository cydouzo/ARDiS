#include "parse_reaction.hpp"
#include "reactionDiffusionSystem/simulation.hpp"

std::string arrowStr = "->";
reaction_holder parse_reaction(const std::string &descriptor) {
    auto arrowPos = descriptor.find(arrowStr);
    if (arrowPos == std::string::npos) {
        throw std::invalid_argument(descriptor +
                                    " : the descriptor must contain an arrow "
                                    "-> to indicate lhs and rhs.");
    }
    if (descriptor.find(arrowStr, arrowPos + 1) != std::string::npos) {
        throw std::invalid_argument(
            descriptor +
            " : the descriptor must not contain more than one arrow ->");
    }
    auto lhs = descriptor.substr(0, arrowPos);
    auto rhs = descriptor.substr(arrowPos + 2, std::string::npos);

    trim(lhs);
    trim(rhs);

    static auto isEmpty = [](const std::string &str) {
        return str.length() == 0 ||
               str.find_first_not_of(' ') == std::string::npos;
    };

    static auto treatSideWithPlus = [](const std::string &s,
                                       std::size_t plusPos) {
        auto pType1 = trim_copy(s.substr(0, plusPos));
        std::string pType2;
        pType2 = trim_copy(s.substr(plusPos + 1, std::string::npos));

        return std::make_tuple(pType1, pType2);
    };

    // Convert string to stochcoeff
    static auto getStochCoeff = [](const std::string &s) {
        std::string::size_type sRem = 0;
        int weight = 1;
        try {
            weight = std::stoi(s, &sRem); // remove parentheses
        } catch (const std::exception &e) {
        }
        std::string speciesName = s.substr(sRem);
        if (isEmpty(speciesName)) {
            weight = 1;
            speciesName = s;
        }
        trim(speciesName);
        return stochCoeff(speciesName, weight);
    };

    static auto getReactionSide = [](std::string &s,
                                     std::vector<stochCoeff> &reactionSide) {
        int plusPos = s.find('+');
        while (plusPos != std::string::npos) {
            std::string species;
            std::tie(species, s) = treatSideWithPlus(s, plusPos);
            if (!isEmpty(species))
                reactionSide.push_back(getStochCoeff(species));
            plusPos = s.find('+');
        }
        if (!isEmpty(s))
            reactionSide.push_back(getStochCoeff(s));
        return reactionSide;
    };

    std::vector<stochCoeff> input;
    std::vector<stochCoeff> output;
    getReactionSide(lhs, input);
    getReactionSide(rhs, output);

    return reaction_holder(input, output);
}

std::string reverse_reaction(const std::string &descriptor) {
    auto arrowPos = descriptor.find(arrowStr);
    if (arrowPos == std::string::npos) {
        throw std::invalid_argument(descriptor +
                                    " : the descriptor must contain an arrow "
                                    "-> to indicate lhs and rhs.");
    }
    if (descriptor.find(arrowStr, arrowPos + 1) != std::string::npos) {
        throw std::invalid_argument(
            descriptor +
            "the descriptor must not contain more than one arrow ->");
    }
    auto lhs = descriptor.substr(0, arrowPos);
    auto rhs = descriptor.substr(arrowPos + 2, std::string::npos);

    return rhs + "->" + lhs;
}